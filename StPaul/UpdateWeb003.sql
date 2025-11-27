BEGIN TRAN
-- Inserting records from WEB003 to BIF010
INSERT INTO advanced.BIF010 (
    C_CUSTOMER,
    C_PHONETYPE,
    C_PHONENUMBER,
    T_UPDATED,
	I_contactinfoid
)
SELECT 
    W.C_CUSTOMER,              -- Customer from WEB003
    'E3',                      -- Static value for C_PHONETYPE
    W.C_EMAIL,                 -- Email from WEB003 as PhoneNumber
    GETDATE() AS T_UPDATED,    -- Using Today's date
	ABS(CAST(CAST(NEWID() AS VARBINARY) AS BIGINT)) as I_contactinfoid -- Adding an additional unique value to later match with the BIF010PK
FROM advanced.WEB003 W
WHERE W.I_WEB003PK = (
    SELECT MAX(I_WEB003PK)
    FROM advanced.WEB003
    WHERE C_CUSTOMER = W.C_CUSTOMER
)AND NOT EXISTS (
    SELECT 1
    FROM advanced.BIF010 B
    WHERE B.C_CUSTOMER = W.C_CUSTOMER
      AND B.C_PHONETYPE = 'E3'
      AND B.C_PHONENUMBER = W.C_EMAIL
) --73285

-- Checking number of records in BIF010 73285
SELECT * FROM BIF010 WHERE C_PHONETYPE='E3'

-- Update contactinfoid with the pk in BIF010
UPDATE A SET I_CONTACTINFOID=I_BIF010PK FROM BIF010 A WHERE C_PHONETYPE='E3'
rollback tran