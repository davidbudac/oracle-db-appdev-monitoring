-- =============================================================================
-- generate_traffic.sql
-- Enqueue-only traffic producer. Runs 50 rounds then exits (entrypoint.sh
-- restarts the session to prevent memory leaks).
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

DECLARE
    v_enqueue_count PLS_INTEGER;

    PROCEDURE enqueue_messages(
        p_queue  IN VARCHAR2,
        p_count  IN PLS_INTEGER,
        p_prefix IN VARCHAR2,
        p_round  IN PLS_INTEGER
    ) IS
        l_props DBMS_AQ.MESSAGE_PROPERTIES_T;
        l_opts  DBMS_AQ.ENQUEUE_OPTIONS_T;
        l_msgid RAW(16);
        l_pay   PDBADMIN.AQ_TEST_PAYLOAD;
    BEGIN
        FOR i IN 1..p_count LOOP
            l_pay := PDBADMIN.AQ_TEST_PAYLOAD(
                i, p_prefix || ' round ' || p_round || ' msg ' || i,
                MOD(i, 3) + 1, SYSTIMESTAMP
            );
            DBMS_AQ.ENQUEUE(
                queue_name         => p_queue,
                enqueue_options    => l_opts,
                message_properties => l_props,
                payload            => l_pay,
                msgid              => l_msgid
            );
        END LOOP;
        COMMIT;
    END;

BEGIN
    FOR v_round IN 1..50 LOOP
        DBMS_RANDOM.SEED(TO_CHAR(SYSTIMESTAMP, 'SSSSSFF3'));

        -- HEALTHY_Q: 3-5 messages per round
        v_enqueue_count := TRUNC(DBMS_RANDOM.VALUE(3, 6));
        enqueue_messages('PDBADMIN.HEALTHY_Q', v_enqueue_count, 'healthy', v_round);

        -- BACKLOG_Q: 5-8 messages per round
        v_enqueue_count := TRUNC(DBMS_RANDOM.VALUE(5, 9));
        enqueue_messages('PDBADMIN.BACKLOG_Q', v_enqueue_count, 'backlog', v_round);

        -- ERRORS_Q: 2 messages per round
        enqueue_messages('PDBADMIN.ERRORS_Q', 2, 'error-prone', v_round);

        -- MISCONFIG_Q: 1 message per round (dequeue disabled, accumulates)
        BEGIN
            enqueue_messages('PDBADMIN.MISCONFIG_Q', 1, 'stuck', v_round);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;

        DBMS_OUTPUT.PUT_LINE('[enqueue round ' || v_round || '/50] done');
        DBMS_SESSION.SLEEP(10);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('[traffic-generator] 50 rounds complete, exiting.');
END;
/

EXIT;
