SET serveroutput ON;

DECLARE
    CURSOR cur_trans_main IS
    SELECT * 
    FROM new_transactions;

    prev_trans_no new_transactions.transaction_no%TYPE := 0;

    CURSOR cur_trans_sub IS
    SELECT * 
    FROM new_transactions 
    WHERE transaction_no = prev_trans_no;

    --Global variables
    v_credit CONSTANT CHAR := 'C';
    v_debit CONSTANT CHAR := 'D';
    total_debit NUMBER := 0;
    total_credit NUMBER := 0;
    def_trans_type CHAR(1);
    curr_account_balance NUMBER;
    acct_no_count NUMBER;
    error_msg VARCHAR2(100);
    trans_no_count NUMBER;

    --User-defined EXCEPTIONS
    missing_transaction_number EXCEPTION;
    invalid_transaction_type EXCEPTION;
    negative_transaction_amount EXCEPTION;
    invalid_account_number EXCEPTION;
    unequal_debit_credit EXCEPTION;

/*
**  Program Name: Anonymous Block
**  Author: Shiana Khehra
**  Created: March 19, 2022
**  Description: Contains a for loop that fetches unique transaction numbers from cur_trans_main based on new_transactions table which can then be passed 
**               to inner cursor(cur_trans_sub) loop.              
*/	
BEGIN
    --Fetches rows from cursor based on new_transactions table
    FOR rec_trans_main IN cur_trans_main LOOP

    total_debit := 0;
    total_credit := 0;

    /*
    **  Program Name: Anonymous Block
    **  Author: Shiana Khehra
    **  Created: March 19, 2022
    **  Description: Contains a nested cursor loop that receives unique transaction numbers from outer loop and checks for any errors in those transactions. 
    **               If no errors exists, it deletes transactions from new_transactions table and add them to transaction_history and transaction_detail tables
    **               as well as update their account balance. However, if an error exists, it handles those exceptions appropriately without affecting the
    **               processing of subsequent rows.
    */
    BEGIN
        --Checks if transaction number is Null.
        IF rec_trans_main.transaction_no IS NULL THEN
            RAISE missing_transaction_number;
        END IF;

        --Only allows passing of unique transaction numbers ahead.
        IF rec_trans_main.transaction_no != prev_trans_no THEN

            prev_trans_no := rec_trans_main.transaction_no;

            --It traverses a cursor which contains the transaction numbers it receives from outer loop. 
            FOR rec_trans_sub IN cur_trans_sub LOOP

                --Checks if account number of the transaction actually exists.
                SELECT COUNT(*)
                INTO acct_no_count
                FROM account
                WHERE account_no = rec_trans_sub.account_no;

                --Checks if account number is valid.
                IF acct_no_count = 0 THEN
                    RAISE invalid_account_number;
                END IF;

                --Checks if transaction type is valid.
                IF rec_trans_sub.transaction_type NOT IN (v_credit, v_debit) THEN
                    RAISE invalid_transaction_type;
                END IF;

                --Checks if transaction amount is valid;
                IF rec_trans_sub.transaction_amount <= 0 THEN
                    RAISE negative_transaction_amount;
                END IF;

                --Calculates total credit and debit of transaction based on transaction type;
                IF rec_trans_sub.transaction_type = v_credit THEN
                    total_credit := rec_trans_sub.transaction_amount + total_credit;
                    ELSIF rec_trans_sub.transaction_type = v_debit THEN
                    total_debit := rec_trans_sub.transaction_amount + total_debit;
                END IF;

                --Retreives the default transaction type.
                SELECT default_trans_type
                INTO def_trans_type
                FROM account_type NATURAL JOIN account
                WHERE account_no = rec_trans_sub.account_no;

                --Retrieves the current account balance of the account numbers involved in the transaction.
                SELECT account_balance
                INTO curr_account_balance
                FROM account
                WHERE account_no = rec_trans_sub.account_no;

                --Updates the account balance after processing transactions.
                IF def_trans_type = rec_trans_sub.transaction_type THEN
                    UPDATE account
                    SET account_balance = curr_account_balance + rec_trans_sub.transaction_amount
                    WHERE account_no = rec_trans_sub.account_no;
                ELSE
                    UPDATE account
                    SET account_balance = curr_account_balance - rec_trans_sub.transaction_amount
                    WHERE account_no = rec_trans_sub.account_no;
                END IF;

                --Checks if the information of a particular transaction already exists in the transaction_history table.
                SELECT COUNT(*) 
                INTO trans_no_count
                FROM transaction_history
                WHERE transaction_no = prev_trans_no;

                --If a particular transaction does not exist in transaction_history, it adds it into the table.
                IF trans_no_count = 0 THEN
                    INSERT INTO transaction_history VALUES (prev_trans_no, rec_trans_main.transaction_date, rec_trans_main.description);
                END IF;

                INSERT INTO transaction_detail VALUES (rec_trans_sub.account_no, rec_trans_sub.transaction_no, rec_trans_sub.transaction_type, rec_trans_sub.transaction_amount);

            END LOOP;

            DELETE FROM new_transactions
            WHERE transaction_no = prev_trans_no;

        END IF;

        --Checks if total debit and credit of a transaction are equal.
        IF total_credit != total_debit THEN
            RAISE unequal_debit_credit;
        END IF;

    EXCEPTION 
        WHEN missing_transaction_number THEN
            ROLLBACK;
            INSERT INTO wkis_error_log VALUES (NULL, rec_trans_main.transaction_date, rec_trans_main.description, 'Transaction is having a NULL transaction number');

        WHEN invalid_transaction_type THEN
            ROLLBACK;
            INSERT INTO wkis_error_log VALUES (rec_trans_main.transaction_no, rec_trans_main.transaction_date, rec_trans_main.description, 'Transaction is having an invalid transaction type. It should either be "C" or "D"');

        WHEN negative_transaction_amount THEN
            ROLLBACK;
            INSERT INTO wkis_error_log VALUES (rec_trans_main.transaction_no, rec_trans_main.transaction_date, rec_trans_main.description, 'Transaction amount for this transaction is either negative or 0. Transaction amount can only be greater than 0.');

        WHEN invalid_account_number THEN
            ROLLBACK;
            INSERT INTO wkis_error_log VALUES (rec_trans_main.transaction_no, rec_trans_main.transaction_date, rec_trans_main.description, 'Account number of the transaction does not exist.');

        WHEN unequal_debit_credit THEN
            ROLLBACK;
            INSERT INTO wkis_error_log VALUES (rec_trans_main.transaction_no, rec_trans_main.transaction_date, rec_trans_main.description, 'Transaction cannot be processed because its debit and credit are not equal. It violates accounting rules.');

        WHEN OTHERS THEN
            ROLLBACK;
            error_msg := SQLERRM;
            INSERT INTO wkis_error_log VALUES (rec_trans_main.transaction_no, rec_trans_main.transaction_date, rec_trans_main.description, error_msg);

    END;

    COMMIT;

    END LOOP;

END;
/