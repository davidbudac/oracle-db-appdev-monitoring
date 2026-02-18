-- =============================================================================
-- dequeue_messages.sql
-- Consumer simulation. Runs 50 rounds of dequeue activity then exits
-- (entrypoint.sh restarts the session).
--
-- Stop this container to simulate a consumer outage — messages will pile up.
-- Start it again to watch the backlog drain.
--
-- Dequeue rates are tuned so that:
--   - With traffic-generator running: queues grow slowly (enqueue > dequeue)
--   - With traffic-generator stopped: queues drain visibly within minutes
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
    v_dequeue_count PLS_INTEGER;
    v_dequeued      PLS_INTEGER;

    -- Dequeue up to N messages for a consumer (NO_WAIT, never blocks)
    PROCEDURE dequeue_messages(
        p_queue    IN VARCHAR2,
        p_consumer IN VARCHAR2,
        p_max      IN PLS_INTEGER,
        p_dequeued OUT PLS_INTEGER
    ) IS
        l_opts  DBMS_AQ.DEQUEUE_OPTIONS_T;
        l_props DBMS_AQ.MESSAGE_PROPERTIES_T;
        l_msgid RAW(16);
        l_pay   PDBADMIN.AQ_TEST_PAYLOAD;
    BEGIN
        p_dequeued := 0;
        l_opts.consumer_name := p_consumer;
        l_opts.wait          := DBMS_AQ.NO_WAIT;
        l_opts.navigation    := DBMS_AQ.FIRST_MESSAGE;

        FOR i IN 1..p_max LOOP
            BEGIN
                DBMS_AQ.DEQUEUE(
                    queue_name         => p_queue,
                    dequeue_options    => l_opts,
                    message_properties => l_props,
                    payload            => l_pay,
                    msgid              => l_msgid
                );
                COMMIT;
                p_dequeued := p_dequeued + 1;
                l_opts.navigation := DBMS_AQ.NEXT_MESSAGE;
            EXCEPTION
                WHEN OTHERS THEN
                    COMMIT;
                    EXIT;
            END;
        END LOOP;
    END;

BEGIN
    FOR v_round IN 1..50 LOOP
        DBMS_RANDOM.SEED(TO_CHAR(SYSTIMESTAMP, 'SSSSSFF3'));

        -----------------------------------------------------------------------
        -- HEALTHY_Q: 3 subscribers
        --   Traffic gen enqueues 3-5/round. Each message needs ALL subscribers
        --   to dequeue before it leaves READY. Drain ~4-6 per subscriber/round
        --   so the queue drains when producer is stopped.
        -----------------------------------------------------------------------
        -- SUB_ALPHA: fast consumer — drain up to 50
        dequeue_messages('PDBADMIN.HEALTHY_Q', 'SUB_ALPHA', 50, v_dequeued);

        -- SUB_BETA: medium consumer — dequeue 3-6
        v_dequeue_count := TRUNC(DBMS_RANDOM.VALUE(3, 7));
        dequeue_messages('PDBADMIN.HEALTHY_Q', 'SUB_BETA', v_dequeue_count, v_dequeued);

        -- SUB_GAMMA: slower consumer — dequeue 2-4
        v_dequeue_count := TRUNC(DBMS_RANDOM.VALUE(2, 5));
        dequeue_messages('PDBADMIN.HEALTHY_Q', 'SUB_GAMMA', v_dequeue_count, v_dequeued);

        -----------------------------------------------------------------------
        -- BACKLOG_Q: 2 subscribers
        --   Traffic gen enqueues 5-8/round. Dequeue enough to drain when
        --   producer is stopped, but still lag slightly when producer runs.
        -----------------------------------------------------------------------
        -- SUB_FAST: dequeue 4-7
        v_dequeue_count := TRUNC(DBMS_RANDOM.VALUE(4, 8));
        dequeue_messages('PDBADMIN.BACKLOG_Q', 'SUB_FAST', v_dequeue_count, v_dequeued);

        -- SUB_SLOW: dequeue 3-5
        v_dequeue_count := TRUNC(DBMS_RANDOM.VALUE(3, 6));
        dequeue_messages('PDBADMIN.BACKLOG_Q', 'SUB_SLOW', v_dequeue_count, v_dequeued);

        DBMS_OUTPUT.PUT_LINE('[dequeue round ' || v_round || '/50] done');
        DBMS_SESSION.SLEEP(5);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('[dequeue-worker] 50 rounds complete, exiting.');
END;
/

EXIT;
