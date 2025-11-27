USE [UC2019_V4]
GO

/****** Object:  StoredProcedure [ADVANCED].[GETBILLINGHISTORYWITHBILLNUM]    Script Date: 2/20/2025 1:49:16 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [ADVANCED].[GETBILLINGHISTORYWITHBILLNUM]      
    @Customer VARCHAR(15),      
    @Account VARCHAR(15),      
    @BillStartDate VARCHAR(15),
    @BillEndDate VARCHAR(15),
    @RtnValue INT OUTPUT      
AS      
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Flag SMALLINT,
            @ReturnAccountStatus VARCHAR(2),      
            @ReturnPIN VARCHAR(10),      
            @ReturnCollectionStatus VARCHAR(2),      
            @ReturnCustomerAccountID DECIMAL(15,0),
            @ParsedBillStartDate DATE,
            @ParsedBillEndDate DATE;

    -- Parse dates once to avoid multiple conversions
    BEGIN TRY
        SET @ParsedBillStartDate = CONVERT(DATE, @BillStartDate);
        SET @ParsedBillEndDate = CONVERT(DATE, @BillEndDate);
    END TRY
    BEGIN CATCH
        SET @Flag = 0;
        GOTO ErrorHandler;
    END CATCH

    -- Validate account
    EXEC ADVANCED.ValidateAccount @Account, @Flag OUTPUT;
    
    IF @Flag = 1
    BEGIN
        -- Validate customer
        EXEC ADVANCED.ValidateCustomer @Customer, @Flag OUTPUT;
        
        IF @Flag = 1
        BEGIN
            -- Validate customer account relationship
            EXEC ADVANCED.ValidateCustomerAccount 
                @Customer, 
                @Account, 
                @Flag OUTPUT, 
                @ReturnAccountStatus OUTPUT, 
                @ReturnPIN OUTPUT, 
                @ReturnCollectionStatus OUTPUT, 
                @ReturnCustomerAccountID OUTPUT;
            
            IF @Flag = 1
            BEGIN
                -- Return billing history data
                SELECT 
                    1 AS ResponseCode,
                    C_CUSTOMER AS CustomerNumber,
                    C_ACCOUNT AS AccountNumber,
                    I_BILLNUMBER AS BillNumber,
                    D_DUEDATE AS DueDate,
                    D_BILLDATE AS BillDate,
                    Y_CURRENTTRANSACTIONS AS BillAmount,
                    CASE 
                        WHEN C_PLANTYPE LIKE 'L%' THEN BIF951.Y_BALANCEFORWARD
                        ELSE BIF951.Y_BALANCEFORWARD + BIF951.Y_CANCELLEDBILLING + 
                             BIF951.Y_TRANSACTIONSSINCELASTBILL + BIF951.Y_PREVIOUSBILLING 
                    END AS Owing 
                FROM ADVANCED.BIF951
                WHERE C_CUSTOMER = @Customer 
                    AND C_ACCOUNT = @Account 
                    AND D_BILLDATE BETWEEN @ParsedBillStartDate AND @ParsedBillEndDate 
                    AND L_CANCEL = 0 
                    AND L_NOBILL = 0 
                    AND C_BILLTYPE <> 'CB'     
                    AND L_PROCESSED = 1 
                ORDER BY D_BILLDATE DESC;
                
                SET @RtnValue = @Flag;
                RETURN;
            END
        END
    END

ErrorHandler:
    -- Return error result set
    SELECT 
        @Flag AS ResponseCode, 
        '1900-01-01' AS BillDate,
        0 AS BillAmount,
        '1900-01-01' AS DueDate, 
        '' AS CustomerNumber, 
        '' AS AccountNumber,   
        0 AS BillNumber, 
        0 AS Owing;
        
    SET @RtnValue = @Flag;
    RETURN;
END
GO

-- SVN last revision and last change date
-- $Revision: 70182 $ $LastChangedDate: 2019-03-15 16:55:21 -0400 (Fri, 15 Mar 2019) $