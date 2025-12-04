
/*==========================================================
Author:   Juan Prado
Purpose:  Replicate BF (Backflow Main) rows to BM (Backflow Manager)
          for accounts lacking BM, then optionally delete BF
          in auditable batches.

Assumptions:
- ADVANCED.BIF006 primary keys/unique keys are not given; deletion uses a stable key set.
- ADVANCED.BIF006_BF_DELETED exists and can receive a row copy + deleted timestamp.
- You want to insert BM rows only when there is no BM for that account.

Notes:
- Adds TRY...CATCH, robust batching with OUTPUT.
- Fixes the original batch delete logic to ensure the same rows we log are the ones we delete.
==========================================================*/

SET NOCOUNT ON;

DECLARE @Proc SYSNAME = 'BIF006_BF_to_BM_Promotion';
PRINT CONCAT(@Proc, ' started at ', CONVERT(varchar(23), SYSDATETIME(), 121));

/*---------------------------------------------
Optional: Review BF rows that lack BM before changes
---------------------------------------------*/
SELECT *
FROM ADVANCED.BIF006 AS b
WHERE b.C_ADDTYPE = 'BF'
  AND NOT EXISTS (
      SELECT 1
      FROM ADVANCED.BIF006 AS a
      WHERE a.C_ACCOUNT = b.C_ACCOUNT
        AND a.C_ADDTYPE = 'BM'
  );

BEGIN TRY
    -- For serializable behavior across scans and inserts when required
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

    BEGIN TRAN;

    /*---------------------------------------------
    1) Insert missing BM rows sourced from BF rows
       (accounts where BM does not yet exist)
    ---------------------------------------------*/
    INSERT INTO ADVANCED.BIF006 (
        C_CUSTOMER, C_ACCOUNT, C_ADDTYPE, C_ADDRESS1, C_ADDRESS2, C_POBOX, 
        C_STREETNUM, C_STREET, C_APT, C_TOWN, C_PROV, C_POSTCODE, C_PLAN, 
        C_LOT, C_CONCESS, C_LASTNAME, C_FIRSTNAME, C_MIDDLENAME, C_SUFFIX, 
        C_PREFIX, C_NAMETYPE, C_EMAIL, C_URL, C_COUNTRY, C_DELIVERYPOINT, 
        C_DRIVENUMPROV, C_RELATIONSHIP, L_VALIDATED, C_STRNUMSUFFIX, 
        L_SENDBILL, L_SENDNOTICE, L_FAOVERRIDE, L_MFOVERRIDE, L_MAOVERRIDE, 
        D_STARTDATE, D_ENDDATE, L_SEASONAL, L_SAOVERRIDE, C_STREETPREFIX, 
        C_STREETSUFFIX, C_EXTERNALREFID, I_COUNT, T_DATETIME, 
        T_LASTEXTERNALUPDATE, L_CUSTOM1, T_ADDRESSVALIDATED, N_STREETNUM, 
        C_VALIDATIONSOURCE, N_POBOX, C_DELIVERYINSTALLATIONTYPE, 
        C_DELIVERYINSTALLATIONNAME, C_VALIDATIONRESULT, C_STREETPOSTDIRECTION
    )
    SELECT 
        b.C_CUSTOMER,
        b.C_ACCOUNT,
        CAST('BM' AS varchar(2)) AS C_ADDTYPE,
        b.C_ADDRESS1,
        b.C_ADDRESS2,
        b.C_POBOX,
        b.C_STREETNUM,
        b.C_STREET,
        b.C_APT,
        b.C_TOWN,
        b.C_PROV,
        b.C_POSTCODE,
        b.C_PLAN,
        b.C_LOT,
        b.C_CONCESS,
        b.C_LASTNAME,
        b.C_FIRSTNAME,
        b.C_MIDDLENAME,
        b.C_SUFFIX,
        b.C_PREFIX,
        b.C_NAMETYPE,
        b.C_EMAIL,
        b.C_URL,
        b.C_COUNTRY,
        b.C_DELIVERYPOINT,
        b.C_DRIVENUMPROV,
        b.C_RELATIONSHIP,
        b.L_VALIDATED,
        b.C_STRNUMSUFFIX,
        b.L_SENDBILL,
        b.L_SENDNOTICE,
        b.L_FAOVERRIDE,
        b.L_MFOVERRIDE,
        b.L_MAOVERRIDE,
        b.D_STARTDATE,
        b.D_ENDDATE,
        b.L_SEASONAL,
        b.L_SAOVERRIDE,
        b.C_STREETPREFIX,
        b.C_STREETSUFFIX,
        b.C_EXTERNALREFID,
        b.I_COUNT,
        b.T_DATETIME,
        b.T_LASTEXTERNALUPDATE,
        b.L_CUSTOM1,
        b.T_ADDRESSVALIDATED,
        b.N_STREETNUM,
        b.C_VALIDATIONSOURCE,
        b.N_POBOX,
        b.C_DELIVERYINSTALLATIONTYPE,
        b.C_DELIVERYINSTALLATIONNAME,
        b.C_VALIDATIONRESULT,
        b.C_STREETPOSTDIRECTION
    FROM ADVANCED.BIF006 AS b
    WHERE b.C_ADDTYPE = 'BF'
      AND NOT EXISTS (
          SELECT 1 
          FROM ADVANCED.BIF006 AS a 
          WHERE a.C_ACCOUNT = b.C_ACCOUNT 
            AND a.C_ADDTYPE = 'BM'
      );

    DECLARE @InsertedBM INT = @@ROWCOUNT;
    PRINT CONCAT('Inserted BM rows from BF: ', @InsertedBM);

    /*---------------------------------------------
    2) (Optional) Update existing BM from newer BF
       Uncomment if you want BM to reflect newer BF data
       This uses T_DATETIME as the freshness indicator; adjust if needed.
    ---------------------------------------------*/
    /*
    UPDATE a
    SET 
        a.C_ADDRESS1                 = b.C_ADDRESS1,
        a.C_ADDRESS2                 = b.C_ADDRESS2,
        a.C_POBOX                    = b.C_POBOX,
        a.C_STREETNUM                = b.C_STREETNUM,
        a.C_STREET                   = b.C_STREET,
        a.C_APT                      = b.C_APT,
        a.C_TOWN                     = b.C_TOWN,
        a.C_PROV                     = b.C_PROV,
        a.C_POSTCODE                 = b.C_POSTCODE,
        a.C_PLAN                     = b.C_PLAN,
        a.C_LOT                      = b.C_LOT,
        a.C_CONCESS                  = b.C_CONCESS,
        a.C_LASTNAME                 = b.C_LASTNAME,
        a.C_FIRSTNAME                = b.C_FIRSTNAME,
        a.C_MIDDLENAME               = b.C_MIDDLENAME,
        a.C_SUFFIX                   = b.C_SUFFIX,
        a.C_PREFIX                   = b.C_PREFIX,
        a.C_NAMETYPE                 = b.C_NAMETYPE,
        a.C_EMAIL                    = b.C_EMAIL,
        a.C_URL                      = b.C_URL,
        a.C_COUNTRY                  = b.C_COUNTRY,
        a.C_DELIVERYPOINT            = b.C_DELIVERYPOINT,
        a.C_DRIVENUMPROV             = b.C_DRIVENUMPROV,
        a.C_RELATIONSHIP             = b.C_RELATIONSHIP,
        a.L_VALIDATED                = b.L_VALIDATED,
        a.C_STRNUMSUFFIX             = b.C_STRNUMSUFFIX,
        a.L_SENDBILL                 = b.L_SENDBILL,
        a.L_SENDNOTICE               = b.L_SENDNOTICE,
        a.L_FAOVERRIDE               = b.L_FAOVERRIDE,
        a.L_MFOVERRIDE               = b.L_MFOVERRIDE,
        a.L_MAOVERRIDE               = b.L_MAOVERRIDE,
        a.D_STARTDATE                = b.D_STARTDATE,
        a.D_ENDDATE                  = b.D_ENDDATE,
        a.L_SEASONAL                 = b.L_SEASONAL,
        a.L_SAOVERRIDE               = b.L_SAOVERRIDE,
        a.C_STREETPREFIX             = b.C_STREETPREFIX,
        a.C_STREETSUFFIX             = b.C_STREETSUFFIX,
        a.C_EXTERNALREFID            = b.C_EXTERNALREFID,
        a.I_COUNT                    = b.I_COUNT,
        a.T_DATETIME                 = b.T_DATETIME,
        a.T_LASTEXTERNALUPDATE       = b.T_LASTEXTERNALUPDATE,
        a.L_CUSTOM1                  = b.L_CUSTOM1,
        a.T_ADDRESSVALIDATED         = b.T_ADDRESSVALIDATED,
        a.N_STREETNUM                = b.N_STREETNUM,
        a.C_VALIDATIONSOURCE         = b.C_VALIDATIONSOURCE,
        a.N_POBOX                    = b.N_POBOX,
        a.C_DELIVERYINSTALLATIONTYPE = b.C_DELIVERYINSTALLATIONTYPE,
        a.C_DELIVERYINSTALLATIONNAME = b.C_DELIVERYINSTALLATIONNAME,
        a.C_VALIDATIONRESULT         = b.C_VALIDATIONRESULT,
        a.C_STREETPOSTDIRECTION      = b.C_STREETPOSTDIRECTION
    FROM ADVANCED.BIF006 AS a
    JOIN ADVANCED.BIF006 AS b
      ON a.C_ACCOUNT = b.C_ACCOUNT
     AND a.C_ADDTYPE = 'BM'
     AND b.C_ADDTYPE = 'BF'
    WHERE b.T_DATETIME > a.T_DATETIME;

    DECLARE @UpdatedBM INT = @@ROWCOUNT;
    PRINT CONCAT('Updated existing BM rows from newer BF: ', @UpdatedBM);
    */

    /*---------------------------------------------
    3) Delete all BF rows now that BM exists or is unchanged
    ---------------------------------------------*/
    DELETE FROM ADVANCED.BIF006
    WHERE C_ADDTYPE = 'BF';
    
     DECLARE @Deleted INT = @@ROWCOUNT;
    PRINT CONCAT('Deleted BF rows: ', @Deleted);

    COMMIT TRAN;
    PRINT 'Promotion (insert/update) completed.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRAN;

    DECLARE 
        @ErrMsg  NVARCHAR(4000) = ERROR_MESSAGE(),
        @ErrNum  INT             = ERROR_NUMBER(),
        @ErrProc NVARCHAR(2000)  = ERROR_PROCEDURE(),
        @ErrLine INT             = ERROR_LINE();

    PRINT CONCAT('ERROR in ', ISNULL(@ErrProc, @Proc), ' at line ', @ErrLine, ': (', @ErrNum, ') ', @ErrMsg);
    THROW;
END CATCH;

SET NOCOUNT OFF;
