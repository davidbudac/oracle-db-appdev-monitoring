-- =============================================================================
-- dequeue_messages.sql
-- Consumer simulation. Runs 50 rounds of dequeue activity then exits
-- (entrypoint.sh restarts the session).
--
-- Stop this container to simulate a consumer outage — messages will pile up.
-- Start it again to watch the backlog drain.
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

    -- Dequeue and rollback to trigger exceptions (for SUB_FAILING on ERRORS_Q)
    PROCEDURE dequeue_and_rollback(
        p_queue    IN VARCHAR2,
        p_consumer IN VARCHAR2,
        p_max      IN PLS_INTEGER
    ) IS
        l_opts  DBMS_AQ.DEQUEUE_OPTIONS_T;
        l_props DBMS_AQ.MESSAGE_PROPERTIES_T;
        l_msgid RAW(16);
        l_pay   PDBADMIN.AQ_TEST_PAYLOAD;
    BEGIN
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
                ROLLBACK;
                l_opts.navigation := DBMS_AQ.NEXT_MESSAGE;
            EXCEPTION
                WHEN OTHERS THEN
                    ROLLBACK;
                    EXIT;
            END;
        END LOOP;
    END;

BEGIN
    FOR v_round IN 1..50 LOOP
        DBMS_RANDOM.SEED(TO_CHAR(SYSTIMESTAMP, 'SSSSSFF3'));

        -----------------------------------------------------------------------
        -- HEALTHY_Q subscribers
        -----------------------------------------------------------------------
        -- SUB_ALPHA: fast consumer — drain up to 20
        dequeue_messages('PDBADMIN.HEALTHY_Q', 'SUB_ALPHA', 20, v_dequeued);

        -- SUB_BETA: medium consumer — dequeue 1-3
        v_dequeue_count := TRUNC(DBMS_RANDOM.VALUE(1, 4));
        dequeue_messages('PDBADMIN.HEALTHY_Q', 'SUB_BETA', v_dequeue_count, v_dequeued);

        -- SUB_GAMMA: slow consumer — dequeue 0-1
        v_dequeue_count := TRUNC(DBMS_RANDOM.VALUE(0, 2));
        IF v_dequeue_count > 0 THEN
            dequeue_messages('PDBADMIN.HEALTHY_Q', 'SUB_GAMMA', v_dequeue_count, v_dequeued);
        END IF;

        -----------------------------------------------------------------------
        -- BACKLOG_Q subscribers
        -----------------------------------------------------------------------
        -- SUB_FAST: dequeue 1-2
        v_dequeue_count := TRUNC(DBMS_RANDOM.VALUE(1, 3));
        dequeue_messages('PDBADMIN.BACKLOG_Q', 'SUB_FAST', v_dequeue_count, v_dequeued);

        -- SUB_SLOW: dequeue 0-1
        v_dequeue_count := TRUNC(DBMS_RANDOM.VALUE(0, 2));
        IF v_dequeue_count > 0 THEN
            dequeue_messages('PDBADMIN.BACKLOG_Q', 'SUB_SLOW', v_dequeue_count, v_dequeued);
        END IF;

        -----------------------------------------------------------------------
        -- ERRORS_Q subscribers
        -----------------------------------------------------------------------
        -- SUB_OK: dequeue normally (up to 5)
        dequeue_messages('PDBADMIN.ERRORS_Q', 'SUB_OK', 5, v_dequeued);

        -- SUB_FAILING: dequeue + rollback (triggers exception after max_retries=0)
        dequeue_and_rollback('PDBADMIN.ERRORS_Q', 'SUB_FAILING', 5);

        -- MISCONFIG_Q: no dequeue (dequeue is disabled on the queue itself)

        DBMS_OUTPUT.PUT_LINE('[dequeue round ' || v_round || '/50] done');
        DBMS_SESSION.SLEEP(10);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('[dequeue-worker] 50 rounds complete, exiting.');
END;
/

EXIT;
