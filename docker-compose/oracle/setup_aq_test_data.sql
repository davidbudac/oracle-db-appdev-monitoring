-- =============================================================================
-- setup_aq_test_data.sql
-- Creates AQ multi-consumer queues with test data for the AQ monitoring
-- dashboard. Runs as SYS during container initialization.
-- =============================================================================

alter session set container=freepdb1;

-- Additional grants for AQ monitoring views
GRANT SELECT ON dba_queues TO pdbadmin;
GRANT SELECT ON dba_queue_tables TO pdbadmin;
GRANT SELECT ON dba_queue_subscribers TO pdbadmin;
GRANT SELECT ON dba_segments TO pdbadmin;
GRANT SELECT ON dba_tables TO pdbadmin;
GRANT SELECT ON gv_$aq TO pdbadmin;
GRANT aq_administrator_role TO pdbadmin;
GRANT CREATE TYPE TO pdbadmin;

-- Connect as pdbadmin to create AQ objects
-- Note: In container init scripts, we're already connected as SYS.
-- We'll create objects owned by PDBADMIN using ALTER SESSION.

-- Create a payload type
BEGIN
    EXECUTE IMMEDIATE 'CREATE OR REPLACE TYPE pdbadmin.aq_test_payload AS OBJECT (
        msg_id    NUMBER,
        msg_text  VARCHAR2(200),
        priority  NUMBER,
        created   TIMESTAMP
    )';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

-- Queue 1: HEALTHY_Q — multiple subscribers, varying dequeue rates
BEGIN
    DBMS_AQADM.CREATE_QUEUE_TABLE(
        queue_table        => 'PDBADMIN.HEALTHY_QT',
        queue_payload_type => 'PDBADMIN.AQ_TEST_PAYLOAD',
        multiple_consumers => TRUE
    );
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -24001 THEN RAISE; END IF;
END;
/

BEGIN
    DBMS_AQADM.CREATE_QUEUE(
        queue_name  => 'PDBADMIN.HEALTHY_Q',
        queue_table => 'PDBADMIN.HEALTHY_QT',
        max_retries => 5,
        retry_delay => 30,
        retention_time => 3600
    );
    DBMS_AQADM.START_QUEUE(queue_name => 'PDBADMIN.HEALTHY_Q');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -24006 THEN RAISE; END IF;
END;
/

BEGIN
    DBMS_AQADM.ADD_SUBSCRIBER(
        queue_name => 'PDBADMIN.HEALTHY_Q',
        subscriber => SYS.AQ$_AGENT('SUB_ALPHA', NULL, NULL)
    );
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    DBMS_AQADM.ADD_SUBSCRIBER(
        queue_name => 'PDBADMIN.HEALTHY_Q',
        subscriber => SYS.AQ$_AGENT('SUB_BETA', NULL, NULL)
    );
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    DBMS_AQADM.ADD_SUBSCRIBER(
        queue_name => 'PDBADMIN.HEALTHY_Q',
        subscriber => SYS.AQ$_AGENT('SUB_GAMMA', NULL, NULL)
    );
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Enqueue 15 messages to HEALTHY_Q
DECLARE
    v_enqueue_options    DBMS_AQ.ENQUEUE_OPTIONS_T;
    v_message_properties DBMS_AQ.MESSAGE_PROPERTIES_T;
    v_message_handle     RAW(16);
    v_payload            PDBADMIN.AQ_TEST_PAYLOAD;
BEGIN
    FOR i IN 1..15 LOOP
        v_payload := PDBADMIN.AQ_TEST_PAYLOAD(i, 'Healthy message ' || i, 1, SYSTIMESTAMP);
        DBMS_AQ.ENQUEUE(
            queue_name         => 'PDBADMIN.HEALTHY_Q',
            enqueue_options    => v_enqueue_options,
            message_properties => v_message_properties,
            payload            => v_payload,
            msgid              => v_message_handle
        );
    END LOOP;
    COMMIT;
END;
/

-- Queue 2: BACKLOG_Q — high message volume with slow consumers
BEGIN
    DBMS_AQADM.CREATE_QUEUE_TABLE(
        queue_table        => 'PDBADMIN.BACKLOG_QT',
        queue_payload_type => 'PDBADMIN.AQ_TEST_PAYLOAD',
        multiple_consumers => TRUE
    );
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -24001 THEN RAISE; END IF;
END;
/

BEGIN
    DBMS_AQADM.CREATE_QUEUE(
        queue_name  => 'PDBADMIN.BACKLOG_Q',
        queue_table => 'PDBADMIN.BACKLOG_QT',
        max_retries => 3,
        retry_delay => 60,
        retention_time => 7200
    );
    DBMS_AQADM.START_QUEUE(queue_name => 'PDBADMIN.BACKLOG_Q');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -24006 THEN RAISE; END IF;
END;
/

BEGIN
    DBMS_AQADM.ADD_SUBSCRIBER(
        queue_name => 'PDBADMIN.BACKLOG_Q',
        subscriber => SYS.AQ$_AGENT('SUB_FAST', NULL, NULL)
    );
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
    DBMS_AQADM.ADD_SUBSCRIBER(
        queue_name => 'PDBADMIN.BACKLOG_Q',
        subscriber => SYS.AQ$_AGENT('SUB_SLOW', NULL, NULL)
    );
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

-- Enqueue 35 messages to BACKLOG_Q
DECLARE
    v_enqueue_options    DBMS_AQ.ENQUEUE_OPTIONS_T;
    v_message_properties DBMS_AQ.MESSAGE_PROPERTIES_T;
    v_message_handle     RAW(16);
    v_payload            PDBADMIN.AQ_TEST_PAYLOAD;
BEGIN
    FOR i IN 1..30 LOOP
        v_payload := PDBADMIN.AQ_TEST_PAYLOAD(i, 'Backlog message ' || i, 2, SYSTIMESTAMP);
        DBMS_AQ.ENQUEUE(
            queue_name         => 'PDBADMIN.BACKLOG_Q',
            enqueue_options    => v_enqueue_options,
            message_properties => v_message_properties,
            payload            => v_payload,
            msgid              => v_message_handle
        );
    END LOOP;
    -- 5 delayed messages
    FOR i IN 31..35 LOOP
        v_payload := PDBADMIN.AQ_TEST_PAYLOAD(i, 'Delayed backlog message ' || i, 3, SYSTIMESTAMP);
        v_message_properties.delay := 600;
        DBMS_AQ.ENQUEUE(
            queue_name         => 'PDBADMIN.BACKLOG_Q',
            enqueue_options    => v_enqueue_options,
            message_properties => v_message_properties,
            payload            => v_payload,
            msgid              => v_message_handle
        );
    END LOOP;
    COMMIT;
END;
/

-- Gather statistics on the queue tables
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS('PDBADMIN', 'HEALTHY_QT');
    DBMS_STATS.GATHER_TABLE_STATS('PDBADMIN', 'BACKLOG_QT');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
