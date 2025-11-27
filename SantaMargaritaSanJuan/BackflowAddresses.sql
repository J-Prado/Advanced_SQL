-- =============================================
-- BACKFLOW ADDRESS MIGRATION SCRIPT
-- Migration from Backflow Main to Backflow Manager
-- =============================================

-- PHASE 1: ANALYSIS AND VALIDATION
-- =============================================

-- Analyze current Backflow Main and Backflow Manager records
SELECT 
    'Backflow Main' AS AddressType,
    COUNT(*) AS AddressCount,
    COUNT(DISTINCT C_CUSTOMER) AS UniqueCustomers
FROM ADVANCED.BIF006 
WHERE C_ADDTYPE = 'BD'

UNION ALL

SELECT 
    'Backflow Manager' AS AddressType,
    COUNT(*) AS AddressCount,
    COUNT(DISTINCT C_CUSTOMER) AS UniqueCustomers
FROM ADVANCED.BIF006 
WHERE C_ADDTYPE = 'BO';

-- Analyze contact information in both systems
SELECT 
    A.C_ADDTYPE,
    COUNT(*) AS TotalRecords,
    COUNT(B.C_PHONENUMBER) AS RecordsWithPhone,
    COUNT(A.C_EMAIL) AS RecordsWithEmail
FROM ADVANCED.BIF006 A
LEFT JOIN ADVANCED.BIF010 B 
    ON A.C_ADDTYPE = B.C_ADDTYPE 
    AND A.C_CUSTOMER = B.C_CUSTOMER
WHERE A.C_ADDTYPE IN ('BD', 'BO')
GROUP BY A.C_ADDTYPE;

-- Find matching customers between Backflow Main and Backflow Manager
SELECT 
    BM.C_CUSTOMER,
    BM.C_ACCOUNT AS Main_Account,
    BO.C_ACCOUNT AS Manager_Account,
    BM.C_LASTNAME + ', ' + BM.C_FIRSTNAME AS Main_Contact,
    BO.C_LASTNAME + ', ' + BO.C_FIRSTNAME AS Manager_Contact
FROM ADVANCED.BIF006 BM
FULL OUTER JOIN ADVANCED.BIF006 BO 
    ON BM.C_CUSTOMER = BO.C_CUSTOMER
    AND BO.C_ADDTYPE = 'BO'
WHERE BM.C_ADDTYPE = 'BD';

-- PHASE 2: DATA MIGRATION
-- =============================================

-- Update Backflow Manager records with Backflow Main contact info where Manager is missing data
UPDATE BO
SET 
    BO.C_LASTNAME = CASE WHEN BO.C_LASTNAME = '' THEN BM.C_LASTNAME ELSE BO.C_LASTNAME END,
    BO.C_FIRSTNAME = CASE WHEN BO.C_FIRSTNAME = '' THEN BM.C_FIRSTNAME ELSE BO.C_FIRSTNAME END,
    BO.C_EMAIL = CASE WHEN BO.C_EMAIL = '' THEN BM.C_EMAIL ELSE BO.C_EMAIL END,
    BO.C_ADDRESS1 = CASE WHEN BO.C_ADDRESS1 = '' THEN BM.C_ADDRESS1 ELSE BO.C_ADDRESS1 END,
    BO.C_ADDRESS2 = CASE WHEN BO.C_ADDRESS2 = '' THEN BM.C_ADDRESS2 ELSE BO.C_ADDRESS2 END,
    BO.C_TOWN = CASE WHEN BO.C_TOWN = '' THEN BM.C_TOWN ELSE BO.C_TOWN END,
    BO.C_PROV = CASE WHEN BO.C_PROV = '' THEN BM.C_PROV ELSE BO.C_PROV END,
    BO.C_POSTCODE = CASE WHEN BO.C_POSTCODE = '' THEN BM.C_POSTCODE ELSE BO.C_POSTCODE END
FROM ADVANCED.BIF006 BO
INNER JOIN ADVANCED.BIF006 BM 
    ON BO.C_CUSTOMER = BM.C_CUSTOMER
    AND BM.C_ADDTYPE = 'BD'
WHERE BO.C_ADDTYPE = 'BO';

-- Migrate phone numbers from Backflow Main to Backflow Manager
-- First, identify existing phone records
MERGE INTO ADVANCED.BIF010 AS Target
USING (
    SELECT 
        BM.C_CUSTOMER,
        BM.C_ACCOUNT,
        BM_PHONE.C_PHONETYPE,
        BM_PHONE.C_PHONENUMBER,
        'BO' AS C_ADDTYPE,
        BM_PHONE.L_PREFERRED,
        BM_PHONE.C_CONTACTTIMES,
        GETDATE() AS T_UPDATED
    FROM ADVANCED.BIF006 BM
    INNER JOIN ADVANCED.BIF010 BM_PHONE 
        ON BM.C_CUSTOMER = BM_PHONE.C_CUSTOMER 
        AND BM_PHONE.C_ADDTYPE = 'BO'
    WHERE BM.C_ADDTYPE = 'BO'
) AS Source
ON Target.C_CUSTOMER = Source.C_CUSTOMER 
    AND Target.C_ADDTYPE = Source.C_ADDTYPE
    AND Target.C_PHONETYPE = Source.C_PHONETYPE
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        C_CUSTOMER, C_ACCOUNT, C_PHONETYPE, C_PHONENUMBER, 
        C_ADDTYPE, L_PREFERRED, C_CONTACTTIMES, T_UPDATED,
        L_CUSTOM1, M_NOTES, I_CONTACTINFOID
    )
    VALUES (
        Source.C_CUSTOMER, Source.C_ACCOUNT, Source.C_PHONETYPE, Source.C_PHONENUMBER,
        Source.C_ADDTYPE, Source.L_PREFERRED, Source.C_CONTACTTIMES, Source.T_UPDATED,
        0, '', 0
    )
WHEN MATCHED AND Target.C_PHONENUMBER != Source.C_PHONENUMBER THEN
    UPDATE SET 
        Target.C_PHONENUMBER = Source.C_PHONENUMBER,
        Target.T_UPDATED = GETDATE();

-- Create Backflow Manager records for customers who only have Backflow Main
INSERT INTO ADVANCED.BIF006 (
    C_CUSTOMER, C_ACCOUNT, C_ADDTYPE, C_ADDRESS1, C_ADDRESS2,
    C_STREETNUM, C_STREET, C_TOWN, C_PROV, C_POSTCODE,
    C_LASTNAME, C_FIRSTNAME, C_EMAIL, C_COUNTRY,
    L_SENDBILL, L_SENDNOTICE
)
SELECT 
    BM.C_CUSTOMER,
    BM.C_ACCOUNT,
    'BO' AS C_ADDTYPE,
    BM.C_ADDRESS1,
    BM.C_ADDRESS2,
    BM.C_STREETNUM,
    BM.C_STREET,
    BM.C_TOWN,
    BM.C_PROV,
    BM.C_POSTCODE,
    BM.C_LASTNAME,
    BM.C_FIRSTNAME,
    BM.C_EMAIL,
    BM.C_COUNTRY,
    BM.L_SENDBILL,
    BM.L_SENDNOTICE
FROM ADVANCED.BIF006 BM
LEFT JOIN ADVANCED.BIF006 BO 
    ON BM.C_CUSTOMER = BO.C_CUSTOMER 
    AND BO.C_ADDTYPE = 'BO'
WHERE BM.C_ADDTYPE = 'BD'
    AND BO.C_CUSTOMER IS NULL;

-- PHASE 3: CLEANUP AND DECOMMISSIONING
-- =============================================

-- First, delete phone records associated with Backflow Main
DELETE FROM ADVANCED.BIF010 
WHERE C_ADDTYPE = 'BM';

-- Then, delete the Backflow Main address records
DELETE FROM ADVANCED.BIF006 
WHERE C_ADDTYPE = 'BM';

-- PHASE 4: VALIDATION AND REPORTING
-- =============================================

-- Verify no Backflow Main records remain
SELECT 
    COUNT(*) AS RemainingBackflowMainRecords
FROM ADVANCED.BIF006 
WHERE C_ADDTYPE = 'BM';

-- Count current Backflow Manager records
SELECT 
    COUNT(*) AS CurrentBackflowManagerRecords
FROM ADVANCED.BIF006 
WHERE C_ADDTYPE = 'BO';

-- Verify phone records are properly associated
SELECT 
    C_ADDTYPE,
    COUNT(*) AS PhoneRecordCount
FROM ADVANCED.BIF010
WHERE C_ADDTYPE IN ('BD', 'BO')
GROUP BY C_ADDTYPE;

-- Sample of migrated records for validation
SELECT TOP 20
    BO.C_CUSTOMER,
    BO.C_LASTNAME,
    BO.C_FIRSTNAME,
    BO.C_EMAIL,
    BO.C_ADDRESS1,
    P.C_PHONENUMBER
FROM ADVANCED.BIF006 BO
LEFT JOIN ADVANCED.BIF010 P 
    ON BO.C_CUSTOMER = P.C_CUSTOMER 
    AND P.C_ADDTYPE = 'BO'
WHERE BO.C_ADDTYPE = 'BO'

-- Final summary report
SELECT 
    'Migration Complete' AS Status,
    (SELECT COUNT(*) FROM ADVANCED.BIF006 WHERE C_ADDTYPE = 'BO') AS BackflowManagerRecords,
    (SELECT COUNT(*) FROM ADVANCED.BIF010 WHERE C_ADDTYPE = 'BO') AS BackflowManagerPhones,
    (SELECT COUNT(*) FROM ADVANCED.BIF006 WHERE C_ADDTYPE = 'BM') AS RemainingBackflowMain,
    GETDATE() AS CompletionTime;