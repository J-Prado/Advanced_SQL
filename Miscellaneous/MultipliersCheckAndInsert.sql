-- =============================================
-- Script: Add Multipliers for RE Account Type with Service 30
-- Description: Identify RE accounts missing multiplier 1 and insert required records
-- =============================================

SET NOCOUNT ON;

BEGIN TRY
    -- =================================================================
    -- STEP 1: ANALYSIS - Check existing multipliers
    -- =================================================================
    PRINT 'Step 1: Analyzing existing account type, service, and multiplier combinations...';
    
    SELECT 
        a.c_accounttype, 
        b.c_service, 
        c.i_multiplier,
        COUNT(*) as record_count
    FROM UC2019_V4.ADVANCED.bif003 a 
    JOIN UC2019_V4.ADVANCED.bif004 b ON a.c_account = b.c_account 
    LEFT OUTER JOIN UC2019_V4.ADVANCED.bif205 c ON b.i_serviceid = c.i_servgrpid 
    WHERE c_company = 1 
        AND c_division = 2 
        AND c_accounttype = 'RE' 
        AND c_service = 30
    GROUP BY a.c_accounttype, b.c_service, c.i_multiplier
    ORDER BY c.i_multiplier;
    
    -- =================================================================
    -- STEP 2: IDENTIFY - Records needing multiplier 1
    -- =================================================================
    PRINT 'Step 2: Identifying accounts that need multiplier 1 added...';
    
    DECLARE @AccountsNeedingMultiplier INT;
    
    SELECT 
        @AccountsNeedingMultiplier = COUNT(*),
        a.C_CUSTOMER,
        a.c_account, 
        a.c_accounttype, 
        b.c_service 
    INTO #AccountsToUpdate
    FROM UC2019_V4.ADVANCED.bif003 a 
    JOIN UC2019_V4.ADVANCED.bif004 b ON a.c_account = b.c_account 
    WHERE c_company = 1 
        AND c_division = 2 
        AND c_accounttype = 'RE' 
        AND c_service = 30
    GROUP BY a.c_customer, a.c_account, a.c_accounttype, b.c_service;
    
    PRINT '  Accounts identified for update: ' + CAST(@AccountsNeedingMultiplier AS VARCHAR(10));
    
    -- =================================================================
    -- STEP 3: BACKUP - Create backup before modifications
    -- =================================================================
    PRINT 'Step 3: Creating backup of BIF205...';
    
    IF OBJECT_ID('tempdb..#BIF205_BACKUP') IS NOT NULL
        DROP TABLE #BIF205_BACKUP;
        
    SELECT * 
    INTO #BIF205_BACKUP
    FROM UC2019_V4.ADVANCED.bif205;
    
    PRINT '  Backup created with ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' records';
    
    -- =================================================================
    -- STEP 4: PREPARATION - Get next available primary keys
    -- =================================================================
    PRINT 'Step 4: Preparing for insertion...';
    
    DECLARE @MaxPK INT, @RecordsToInsert INT;
    
    SELECT @MaxPK = MAX(ISNULL(i_bif205PK, 0)) 
    FROM UC2019_V4.ADVANCED.bif205;
    
    SELECT @RecordsToInsert = COUNT(DISTINCT b.i_serviceid)
    FROM UC2019_V4.ADVANCED.bif003 a 
    JOIN UC2019_V4.ADVANCED.bif004 b ON a.c_account = b.c_account 
    WHERE c_company = 1 
        AND c_division = 2 
        AND c_accounttype = 'RE' 
        AND c_service = 30;
    
    PRINT '  Current max PK: ' + CAST(@MaxPK AS VARCHAR(10));
    PRINT '  Records to insert: ' + CAST(@RecordsToInsert AS VARCHAR(10));
    
    -- =================================================================
    -- STEP 5: EXECUTION - Insert new multipliers with transaction
    -- =================================================================
    PRINT 'Step 5: Inserting new multiplier records...';
    
    BEGIN TRANSACTION;
    
    WITH BKLFilter AS 
    (
        SELECT DISTINCT b.i_serviceid AS I_SERVGRPID
        FROM UC2019_V4.ADVANCED.bif003 a 
        JOIN UC2019_V4.ADVANCED.bif004 b ON a.c_account = b.c_account 
        WHERE c_company = 1 
            AND c_division = 2 
            AND c_accounttype = 'RE' 
            AND c_service = 30 
    )
    INSERT INTO UC2019_V4.ADVANCED.bif205 (
        I_SERVGRPID, 
        I_MULTIPLIER, 
        N_BASICMULTIPLE, 
        C_NOTES, 
        I_BIF205PK, 
        D_STARTDATE, 
        D_ENDDATE, 
        C_SERVICEGROUP
    )
    SELECT 
        b.i_serviceid, 
        1 AS I_MULTIPLIER, 
        4 AS N_BASICMULTIPLE, 
        '' AS C_NOTES, 
        @MaxPK + (ROW_NUMBER() OVER (ORDER BY b.i_serviceid)) AS I_BIF205PK, 
        b.d_dateinstalled AS D_STARTDATE, 
        '' AS D_ENDDATE, 
        b.c_service AS C_SERVICEGROUP
    FROM UC2019_V4.ADVANCED.bif004 b 
    JOIN BKLFilter c ON b.i_serviceid = c.I_SERVGRPID;
    
    DECLARE @InsertedRows INT = @@ROWCOUNT;
    
    PRINT '  Successfully inserted ' + CAST(@InsertedRows AS VARCHAR(10)) + ' records';
    
    -- =================================================================
    -- STEP 6: VALIDATION - Verify inserted records
    -- =================================================================
    PRINT 'Step 6: Validating inserted records...';
    
    DECLARE @VerifiedCount INT;
    
    SELECT 
        @VerifiedCount = COUNT(*),
        a.c_customer, 
        a.c_account, 
        a.c_accounttype, 
        b.c_service, 
        c.i_multiplier 
    FROM UC2019_V4.ADVANCED.bif003 a 
    JOIN UC2019_V4.ADVANCED.bif004 b ON a.c_account = b.c_account 
    LEFT OUTER JOIN UC2019_V4.ADVANCED.bif205 c ON b.i_serviceid = c.i_servgrpid 
    WHERE c_company = 1 
        AND c_division = 2 
        AND c_accounttype = 'RE' 
        AND c_service = 30 
        AND c.i_multiplier = 1
    GROUP BY a.c_customer, a.c_account, a.c_accounttype, b.c_service, c.i_multiplier;
    
    PRINT '  Verified accounts with multiplier 1: ' + CAST(@VerifiedCount AS VARCHAR(10));
    
    -- =================================================================
    -- STEP 7: FINALIZATION - Commit or rollback
    -- =================================================================
    IF @InsertedRows = @RecordsToInsert AND @VerifiedCount >= @InsertedRows
    BEGIN
        COMMIT TRANSACTION;
        PRINT 'Transaction committed successfully.';
        
        -- Final summary report
        PRINT '=============================================';
        PRINT 'OPERATION COMPLETED SUCCESSFULLY';
        PRINT '=============================================';
        PRINT 'Accounts processed: ' + CAST(@AccountsNeedingMultiplier AS VARCHAR(10));
        PRINT 'Multiplier records inserted: ' + CAST(@InsertedRows AS VARCHAR(10));
        PRINT 'Multiplier value: 1';
        PRINT 'Basic multiple: 4';
        PRINT 'Service: 30';
        PRINT 'Account type: RE';
        PRINT '=============================================';
    END
    ELSE
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('Validation failed: Expected %d records, inserted %d, verified %d', 
                  16, 1, @RecordsToInsert, @InsertedRows, @VerifiedCount);
    END
    
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState INT = ERROR_STATE();
    
    PRINT 'ERROR: Operation failed - ' + @ErrorMessage;
    
    -- Log error details
    SELECT 
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE() AS ErrorState,
        ERROR_PROCEDURE() AS ErrorProcedure,
        ERROR_LINE() AS ErrorLine,
        ERROR_MESSAGE() AS ErrorMessage;
    
    RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END CATCH

-- =================================================================
-- CLEANUP
-- =================================================================
IF OBJECT_ID('tempdb..#AccountsToUpdate') IS NOT NULL
    DROP TABLE #AccountsToUpdate;
    
IF OBJECT_ID('tempdb..#BIF205_BACKUP') IS NOT NULL
    DROP TABLE #BIF205_BACKUP;

PRINT 'Cleanup completed.';