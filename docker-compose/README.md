# Oracle AQ Monitoring Demo Stack

A Docker Compose stack that runs an Oracle 23ai database with multi-consumer Advanced Queuing (AQ) queues, continuous enqueue/dequeue traffic, Prometheus metrics collection, and a Grafana dashboard for monitoring queue health.

## Architecture

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ traffic-generator│     │  dequeue-worker   │     │    free23ai      │
│  (enqueue only)  │────▶│  (dequeue only)   │────▶│  Oracle 23ai DB  │
│  3-8 msgs/round  │     │  2-50 msgs/round  │     │  HEALTHY_Q       │
│  every 10s       │     │  every 5s         │     │  BACKLOG_Q       │
└──────────────────┘     └──────────────────┘     └────────┬─────────┘
                                                           │
                                                  ┌────────▼─────────┐
                                                  │    exporter      │
                                                  │  Oracle Metrics  │
                                                  │  Exporter :9161  │
                                                  └────────┬─────────┘
                                                           │
                                                  ┌────────▼─────────┐
                                                  │   prometheus     │
                                                  │   :9090          │
                                                  └────────┬─────────┘
                                                           │
                                                  ┌────────▼─────────┐
                                                  │    grafana       │
                                                  │   :3000          │
                                                  └──────────────────┘
```

## Containers

| Container | Image | Purpose | Port |
|---|---|---|---|
| `free23ai` | `gvenzl/oracle-free:23.9-slim-faststart` | Oracle 23ai database with AQ queues | 1521 |
| `traffic-generator` | `gvenzl/oracle-free:23.9-slim-faststart` | Continuously enqueues messages into both queues | - |
| `dequeue-worker` | `gvenzl/oracle-free:23.9-slim-faststart` | Continuously dequeues messages from both queues | - |
| `exporter` | `container-registry.oracle.com/database/observability-exporter:2.2.0` | Scrapes Oracle DB metrics and exposes them as Prometheus endpoints | 9161 |
| `prometheus` | `prom/prometheus` | Collects metrics from the exporter | 9090 |
| `grafana` | `grafana/grafana` | Displays the AQ monitoring dashboard | 3000 |

## Queues

Two multi-consumer AQ queues are created during database initialization, both owned by `PDBADMIN` in the `FREEPDB1` pluggable database.

### HEALTHY_Q

A well-behaved queue with three subscribers at different consumption speeds.

| Property | Value |
|---|---|
| Queue table | `HEALTHY_QT` |
| Multiple consumers | YES |
| Max retries | 5 |
| Retry delay | 30s |
| Retention | 3600s (1 hour) |
| Subscribers | `SUB_ALPHA`, `SUB_BETA`, `SUB_GAMMA` |

**Traffic pattern:**
- **Enqueue:** 3-5 messages per round (every 10s)
- **Dequeue:** SUB_ALPHA drains up to 50/round (fast), SUB_BETA 3-6/round (medium), SUB_GAMMA 2-4/round (slow)
- Messages only leave READY state when ALL subscribers have dequeued them, so SUB_GAMMA is the bottleneck

### BACKLOG_Q

A queue designed to accumulate a backlog over time due to slower consumers.

| Property | Value |
|---|---|
| Queue table | `BACKLOG_QT` |
| Multiple consumers | YES |
| Max retries | 3 |
| Retry delay | 60s |
| Retention | 7200s (2 hours) |
| Subscribers | `SUB_FAST`, `SUB_SLOW` |

**Traffic pattern:**
- **Enqueue:** 5-8 messages per round (every 10s)
- **Dequeue:** SUB_FAST 4-7/round, SUB_SLOW 3-5/round (every 5s)
- The initial seed also includes 5 delayed messages (10-minute delay)

### Message payload type

Both queues use the same `PDBADMIN.AQ_TEST_PAYLOAD` object type:

```sql
CREATE TYPE AQ_TEST_PAYLOAD AS OBJECT (
    msg_id    NUMBER,
    msg_text  VARCHAR2(200),
    priority  NUMBER,
    created   TIMESTAMP
);
```

## Scripts

### Database initialization

**`oracle/setup_aq_test_data.sql`** — Runs as SYS during container startup (mounted into `/container-entrypoint-initdb.d/`). It:

1. Switches to `FREEPDB1` pluggable database
2. Grants monitoring privileges to `PDBADMIN` (SELECT on `DBA_QUEUES`, `DBA_QUEUE_TABLES`, `DBA_QUEUE_SUBSCRIBERS`, `DBA_SEGMENTS`, `DBA_TABLES`, `GV_$AQ`, plus `AQ_ADMINISTRATOR_ROLE`)
3. Creates the `AQ_TEST_PAYLOAD` object type
4. Creates `HEALTHY_QT` queue table and `HEALTHY_Q` queue with 3 subscribers
5. Seeds 15 initial messages into `HEALTHY_Q`
6. Creates `BACKLOG_QT` queue table and `BACKLOG_Q` queue with 2 subscribers
7. Seeds 35 initial messages into `BACKLOG_Q` (30 immediate + 5 delayed)
8. Gathers table statistics on both queue tables

### Traffic generator (enqueue)

The `traffic-generator` container runs the enqueue side of the traffic loop.

**`traffic-generator/entrypoint.sh`** — Shell entrypoint that:
1. Polls the database until `HEALTHY_Q` exists in `USER_QUEUES` (the DB healthcheck passes before init scripts finish, so the entrypoint waits for the actual queues)
2. Runs `generate_traffic.sql` via sqlplus in an infinite loop
3. Reconnects on failure with a 15s backoff

**`traffic-generator/generate_traffic.sql`** — PL/SQL anonymous block that:
1. Runs 50 rounds, then exits (the shell restarts it to prevent session/memory leaks)
2. Each round enqueues 3-5 random messages to `HEALTHY_Q` and 5-8 to `BACKLOG_Q`
3. Sleeps 10 seconds between rounds using `DBMS_SESSION.SLEEP`
4. Uses `DBMS_RANDOM` for randomized message counts

### Dequeue worker (dequeue)

The `dequeue-worker` container runs the dequeue side. **Stop this container to simulate a consumer outage** — messages will pile up in the queues. Start it again to watch the backlog drain.

**`dequeue-worker/entrypoint.sh`** — Same pattern as the traffic generator: waits for queues, then runs the SQL in a loop.

**`dequeue-worker/dequeue_messages.sql`** — PL/SQL anonymous block that:
1. Runs 50 rounds, then exits
2. Each round dequeues messages from both queues for each subscriber:
   - `HEALTHY_Q`: SUB_ALPHA up to 50 (drains everything), SUB_BETA 3-6, SUB_GAMMA 2-4
   - `BACKLOG_Q`: SUB_FAST 4-7, SUB_SLOW 3-5
3. Uses `DBMS_AQ.NO_WAIT` so dequeue never blocks — if no messages are available, it moves on
4. Sleeps 5 seconds between rounds

The dequeue rates are tuned so that:
- **With traffic-generator running:** queues grow slowly (enqueue rate slightly exceeds dequeue rate)
- **With traffic-generator stopped:** queues drain visibly within minutes

### Metrics exporter

**`exporter/config.yaml`** — Configures the Oracle Metrics Exporter to connect to `free23ai:1521/freepdb1` as `pdbadmin` and load custom AQ metrics.

**`exporter/aq-monitoring-metrics.yaml`** — Defines 8 custom metrics scraped from the Oracle database:

| # | Context | Description |
|---|---|---|
| 1 | `aq_queue_depth` | Message counts by state (ready, waiting, expired, total) from `GV$AQ` |
| 2 | `aq_queue_table_storage` | Storage size per queue table in MB from `DBA_SEGMENTS` |
| 3 | `aq_queue_table_rows` | Estimated row counts from `DBA_TABLES` optimizer statistics |
| 4 | `aq_queue_config` | Queue settings: enqueue/dequeue enabled, max retries, retry delay, retention |
| 5 | `aq_subscribers` | Subscriber count per queue from `DBA_QUEUE_SUBSCRIBERS` |
| 6 | `aq_queue_table_config` | Queue table config info: recipients type, message grouping, sort order |
| 7 | `aq_throughput` | Ready/waiting/expired snapshot for normal queues (use `deriv()` in Prometheus) |
| 8 | `aq_msg_age` | Average and oldest message age computed from `ENQ_TIME` in `AQ$` queue table views |

> **Note:** `GV$AQ.AVERAGE_WAIT` and `AVERAGE_MSG_AGE` return numeric overflow values in Oracle 23ai for multi-consumer queues. Metric #8 works around this by computing age directly from `ENQ_TIME`.

### Grafana dashboard

**`grafana/dashboards/aq-monitoring.json`** — Pre-provisioned dashboard with these sections:

- **AQ Overview** — Stat panels: total messages, ready messages, avg message age, queue table storage
- **Queue Depth** — Time series: ready/waiting counts, total messages per queue (stacked), avg/oldest message age
- **Queue Table Storage** — Time series: storage size and estimated row count per queue table
- **Queue Configuration** — Table: enqueue/dequeue enabled, max retries, retry delay, retention per queue
- **Subscribers** — Bar chart: subscriber count per queue
- **Throughput** — Time series: ready message rate of change (proxy for throughput)

## Quick start

```bash
cd docker-compose
docker compose up -d
```

Wait ~60 seconds for the database to initialize and queues to be created, then:

- **Grafana:** http://localhost:3000 (admin / grafana)
- **Prometheus:** http://localhost:9090
- **Exporter metrics:** http://localhost:9161/metrics

## Simulating scenarios

### Consumer outage

Stop the dequeue worker to simulate all consumers going down:

```bash
docker compose stop dequeue-worker
```

Watch messages pile up in the Grafana dashboard. Restart to see the backlog drain:

```bash
docker compose start dequeue-worker
```

### Producer outage

Stop the traffic generator to see how queues drain with no new messages:

```bash
docker compose stop traffic-generator
```

### Full reset

Tear everything down and start fresh (removes database volumes):

```bash
docker compose down -v
docker compose up -d
```
