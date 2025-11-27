-- =============================================
-- Script: Add multipliers for RE account type with service 30
-- Description: Identify and add missing multipliers for specific account criteria
-- Created: 2023-01-23
-- =============================================

SET NOCOUNT ON;

BEGIN TRY
    -- =================================================================
    -- STEP 1: DATA ANALYSIS AND VALIDATION
    -- =================================================================
    PRINT 'Step 1: Analyzing and validating source data...';
    
    -- Check BIF003 data
    DECLARE @BIF003Count INT, @BIF003DistinctCount INT, @BIF004Count INT, @BIF205Count INT;
    
    SELECT @BIF003Count = COUNT(*)
    FROM CISV4CONVERSION.ADVANCED.BIF003 
    WHERE C_ACCOUNTTYPE = 'RE' 
        AND C_DIVISION = '02';
    
    PRINT '  BIF003 records (RE accounts, Division 02): ' + CAST(@BIF003Count AS VARCHAR(10));
    
    SELECT @BIF003DistinctCount = COUNT(DISTINCT C_ACCOUNT)
    FROM CISV4CONVERSION.ADVANCED.BIF003 
    WHERE C_ACCOUNTTYPE = 'RE' 
        AND C_DIVISION = '02';
    
    PRINT '  Distinct accounts in BIF003: ' + CAST(@BIF003DistinctCount AS VARCHAR(10));
    
    -- Check BIF004 data
    SELECT @BIF004Count = COUNT(*)
    FROM CISV4CONVERSION.ADVANCED.BIF004 
    WHERE C_SERVICE = '30' 
        AND C_ACCOUNT IN (
            SELECT C_ACCOUNT 
            FROM CISV4CONVERSION.ADVANCED.BIF003 
            WHERE C_ACCOUNTTYPE = 'RE' 
                AND C_DIVISION = '02'
        );
    
    PRINT '  BIF004 records (Service 30, RE accounts): ' + CAST(@BIF004Count AS VARCHAR(10));
    
    -- Check existing BIF205 multipliers
    SELECT @BIF205Count = COUNT(*)
    FROM CISV4CONVERSION.ADVANCED.BIF205 MULTI 
    JOIN CISV4CONVERSION.ADVANCED.BIF004 SERV 
        ON MULTI.I_SERVGRPID = SERV.I_SERVGRPID 
        AND MULTI.C_SERVICEGROUP = SERV.C_SERVICEGROUP
    WHERE MULTI.I_MULTIPLIER = 1 
        AND SERV.C_SERVICE = '30' 
        AND SERV.C_ACCOUNT IN (
            SELECT C_ACCOUNT 
            FROM CISV4CONVERSION.ADVANCED.BIF003 
            WHERE C_ACCOUNTTYPE = 'RE' 
                AND C_DIVISION = '02'
        );
    
    PRINT '  Existing BIF205 multipliers: ' + CAST(@BIF205Count AS VARCHAR(10));
    
    -- =================================================================
    -- STEP 2: CREATE BACKUP TABLES
    -- =================================================================
    PRINT 'Step 2: Creating backup tables...';
    
    -- Backup BIF205
    IF OBJECT_ID('CISV4CONVERSION.ADVANCED.BIF205_BK20230123', 'U') IS NULL
    BEGIN
        SELECT * 
        INTO CISV4CONVERSION.ADVANCED.BIF205_BK20230123 
        FROM CISV4CONVERSION.ADVANCED.BIF205;
        
        DECLARE @BackupCount INT = @@ROWCOUNT;
        PRINT '  BIF205 backup created with ' + CAST(@BackupCount AS VARCHAR(10)) + ' records';
    END
    ELSE
    BEGIN
        PRINT '  BIF205 backup table already exists';
    END
    
    -- Create working table for target accounts
    IF OBJECT_ID('CISV4CONVERSION.DBO.SJCREACCTS', 'U') IS NOT NULL
        DROP TABLE CISV4CONVERSION.DBO.SJCREACCTS;
    
    SELECT 
        C_ACCOUNT, 
        C_SERVICE, 
        I_SERVGRPID 
    INTO CISV4CONVERSION.DBO.SJCREACCTS
    FROM CISV4CONVERSION.ADVANCED.BIF004 
    WHERE C_SERVICE = '30' 
        AND C_ACCOUNT IN (
            SELECT C_ACCOUNT 
            FROM CISV4CONVERSION.ADVANCED.BIF003 
            WHERE C_ACCOUNTTYPE = 'RE' 
                AND C_DIVISION = '02'
        );
    
    PRINT '  Target accounts table created with ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' records';
    
    -- =================================================================
    -- STEP 3: PREPARE FOR DATA INSERTION
    -- =================================================================
    PRINT 'Step 3: Preparing to insert new multipliers...';
    
    -- Get current maximum PK value
    DECLARE @MaxPK INT, @NewRecordsCount INT;
    
    SELECT @MaxPK = MAX(I_BIF205PK) 
    FROM CISV4CONVERSION.ADVANCED.BIF205;
    
    PRINT '  Current maximum I_BIF205PK: ' + CAST(@MaxPK AS VARCHAR(10));
    
    SELECT @NewRecordsCount = COUNT(*)
    FROM CISV4CONVERSION.DBO.SJCREACCTS;
    
    PRINT '  Records to insert: ' + CAST(@NewRecordsCount AS VARCHAR(10));
    
    -- =================================================================
    -- STEP 4: INSERT NEW MULTIPLIERS (WITH TRANSACTION)
    -- =================================================================
    PRINT 'Step 4: Inserting new multipliers...';
    
    BEGIN TRANSACTION;
    
    INSERT INTO CISV4CONVERSION.ADVANCED.BIF205 (
        I_SERVGRPID, 
        I_MULTIPLIER, 
        N_BASICMULTIPLE, 
        D_STARTDATE, 
        C_SERVICEGROUP
    )
    SELECT 
        I_SERVGRPID, 
        1 AS I_MULTIPLIER, 
        4 AS N_BASICMULTIPLE, 
        '2023-01-01' AS D_STARTDATE, 
        '30' AS C_SERVICEGROUP 
    FROM CISV4CONVERSION.DBO.SJCREACCTS;
    
    DECLARE @InsertedRows INT = @@ROWCOUNT;
    
    PRINT '  Successfully inserted ' + CAST(@InsertedRows AS VARCHAR(10)) + ' records';
    
    -- =================================================================
    -- STEP 5: VERIFICATION AND VALIDATION
    -- =================================================================
    PRINT 'Step 5: Verifying inserted data...';
    
    -- Verify the inserted records
    DECLARE @VerifiedCount INT;
    
    SELECT @VerifiedCount = COUNT(*)
    FROM CISV4CONVERSION.DBO.SJCREACCTS A 
    JOIN CISV4CONVERSION.ADVANCED.BIF205 B 
        ON A.I_SERVGRPID = B.I_SERVGRPID 
    WHERE B.I_BIF205PK > @MaxPK;
    
    PRINT '  Verified new records in BIF205: ' + CAST(@VerifiedCount AS VARCHAR(10));
    
    IF @InsertedRows = @VerifiedCount
    BEGIN
        COMMIT TRANSACTION;
        PRINT 'Transaction committed successfully.';
        
        -- Final summary
        PRINT '=============================================';
        PRINT 'OPERATION SUMMARY:';
        PRINT '  Accounts processed: ' + CAST(@NewRecordsCount AS VARCHAR(10));
        PRINT '  Multipliers added: ' + CAST(@InsertedRows AS VARCHAR(10));
        PRINT '  Start date: 2023-01-01';
        PRINT '  Service group: 30';
        PRINT '=============================================';
    END
    ELSE
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('Data validation failed: Inserted %d records but verified %d records', 16, 1, @InsertedRows, @VerifiedCount);
    END
    
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState INT = ERROR_STATE();
    
    PRINT 'ERROR: Operation failed - ' + @ErrorMessage;
    RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END CATCH

-- =================================================================
-- STEP 6: CLEANUP (OPTIONAL - COMMENTED OUT FOR SAFETY)
-- =================================================================
/*
-- Uncomment the following lines if you want to clean up the working table
IF OBJECT_ID('CISV4CONVERSION.DBO.SJCREACCTS', 'U') IS NOT NULL
BEGIN
    DROP TABLE CISV4CONVERSION.DBO.SJCREACCTS;
    PRINT 'Working table cleaned up.';
END
*/