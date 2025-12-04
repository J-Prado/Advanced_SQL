
/*==========================================================
Author:   Juan Prado
Purpose:  Promote BF phone rows to BM where BM is missing,
          then delete BF rows. Includes pre-check report.

Notes:
- Uses SERIALIZABLE isolation to protect MaxID + ROW_NUMBER()
  ID generation from concurrent sessions.
- Corrects alias typo (a.C_ADDTYPE).
- Adds TRY...CATCH with error bubbling.
- Uses SET NOCOUNT ON for cleaner output.
==========================================================*/

SET NOCOUNT ON;

DECLARE @ProcName SYSNAME = 'BF_to_BM_Promotion';
PRINT CONCAT(@ProcName, ' started at ', CONVERT(varchar(23), SYSDATETIME(), 121));

/*---------------------------------------------
Optional: Validation report of BF vs BM recency
---------------------------------------------*/
;WITH BF AS (
    SELECT *
    FROM ADVANCED.BIF010
    WHERE C_ADDTYPE = 'BF'
),
BM AS (
    SELECT *
    FROM ADVANCED.BIF010
    WHERE C_ADDTYPE = 'BM'
)
SELECT 
    b.*,
    a.T_UPDATED AS BM_T_UPDATED,
    CASE 
        WHEN b.T_UPDATED > COALESCE(a.T_UPDATED, '1900-01-01') 
            THEN 'BF is newer - UPDATE NEEDED'
        ELSE 'BM is newer or equal - NO UPDATE NEEDED'
    END AS UPDATE_STATUS
FROM BF AS b
LEFT JOIN BM AS a
    ON a.C_ACCOUNT   = b.C_ACCOUNT
   AND a.C_PHONETYPE = b.C_PHONETYPE;

/*---------------------------------------------
Main transactional block
---------------------------------------------*/
BEGIN TRY
    -- Guard against concurrent generators of I_CONTACTINFOID
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

    BEGIN TRAN;

    /*---------------------------------------------
    1) Stage source rows to be inserted as BM
       (BF rows that do NOT already have a BM peer)
    ---------------------------------------------*/
    ;WITH SourceRows AS (
        SELECT 
            b.C_CUSTOMER,
            b.C_ACCOUNT,
            b.C_PHONETYPE,
            b.C_PHONENUMBER,
            CAST('BM' AS varchar(2)) AS C_ADDTYPE,
            b.T_UPDATED,
            b.L_CUSTOM1,
            b.M_NOTES,
            b.L_PREFERRED,
            b.C_CONTACTTIMES
        FROM ADVANCED.BIF010 AS b
        WHERE b.C_ADDTYPE = 'BF'
          AND NOT EXISTS (
              SELECT 1
              FROM ADVANCED.BIF010 AS a
              WHERE a.C_ACCOUNT   = b.C_ACCOUNT
                AND a.C_PHONETYPE = b.C_PHONETYPE
                AND a.C_ADDTYPE   = 'BM'
          )
    ),
    Numbered AS (
        SELECT 
            SR.*,
            ROW_NUMBER() OVER (ORDER BY SR.C_ACCOUNT, SR.C_PHONETYPE) AS RN
        FROM SourceRows AS SR
    ),
    MaxID AS (
        SELECT COALESCE(MAX(I_CONTACTINFOID), 0) AS MaxID
        FROM ADVANCED.BIF010
    )
    INSERT INTO ADVANCED.BIF010 (
        C_CUSTOMER,
        C_ACCOUNT,
        C_PHONETYPE,
        C_PHONENUMBER,
        C_ADDTYPE,
        T_UPDATED,
        L_CUSTOM1,
        M_NOTES,
        L_PREFERRED,
        C_CONTACTTIMES,
        I_CONTACTINFOID
    )
    SELECT
        n.C_CUSTOMER,
        n.C_ACCOUNT,
        n.C_PHONETYPE,
        n.C_PHONENUMBER,
        n.C_ADDTYPE,
        n.T_UPDATED,
        n.L_CUSTOM1,
        n.M_NOTES,
        n.L_PREFERRED,
        n.C_CONTACTTIMES,
        (m.MaxID + n.RN) AS I_CONTACTINFOID
    FROM Numbered AS n
    CROSS JOIN MaxID AS m;

    DECLARE @Inserted INT = @@ROWCOUNT;
    PRINT CONCAT('Inserted BM rows: ', @Inserted);

    /*---------------------------------------------
    2) (Optional) If you also want to UPDATE existing BM when BF is newer,
       uncomment this block. It updates BM values to match BF where BF.T_UPDATED is newer.
       If you prefer to leave existing BM untouched, keep this commented.
    ---------------------------------------------*/
    /*
    UPDATE a
    SET 
        a.C_PHONENUMBER   = b.C_PHONENUMBER,
        a.T_UPDATED       = b.T_UPDATED,
        a.L_CUSTOM1       = b.L_CUSTOM1,
        a.M_NOTES         = b.M_NOTES,
        a.L_PREFERRED     = b.L_PREFERRED,
        a.C_CONTACTTIMES  = b.C_CONTACTTIMES
    FROM ADVANCED.BIF010 AS a
    JOIN ADVANCED.BIF010 AS b
      ON a.C_ACCOUNT   = b.C_ACCOUNT
     AND a.C_PHONETYPE = b.C_PHONETYPE
     AND a.C_ADDTYPE   = 'BM'
     AND b.C_ADDTYPE   = 'BF'
    WHERE b.T_UPDATED > a.T_UPDATED;

    DECLARE @Updated INT = @@ROWCOUNT;
    PRINT CONCAT('Updated existing BM rows from newer BF: ', @Updated);
    */

    /*---------------------------------------------
    3) Delete all BF rows now that BM exists or is unchanged
    ---------------------------------------------*/
    DELETE FROM ADVANCED.BIF010
    WHERE C_ADDTYPE = 'BF';

    DECLARE @Deleted INT = @@ROWCOUNT;
    PRINT CONCAT('Deleted BF rows: ', @Deleted);

    COMMIT TRAN;
    PRINT CONCAT(@ProcName, ' completed successfully at ', CONVERT(varchar(23), SYSDATETIME(), 121));
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRAN;

    DECLARE 
        @ErrMsg  NVARCHAR(4000) = ERROR_MESSAGE(),
        @ErrNum  INT             = ERROR_NUMBER(),
        @ErrProc NVARCHAR(2000)  = ERROR_PROCEDURE(),
        @ErrLine INT             = ERROR_LINE();

    PRINT CONCAT('ERROR in ', ISNULL(@ErrProc, @ProcName), ' at line ', @ErrLine, ': (', @ErrNum, ') ', @ErrMsg);
    THROW;  -- Bubble up to caller/logging
END CATCH;

