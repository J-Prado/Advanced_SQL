PROCEDURE CISDATA!GETPAYMENTHISTORY
CREATE PROCEDURE CISDATA!GETPAYMENTHISTORY
	@customer	VARCHAR(15),
	@account	VARCHAR(15),
	@records	INT,
	@rtnvalue	SMALLINT OUTPUT

AS
	SET NOCOUNT ON
	DECLARE 	@lcString VARCHAR(600),
			@lnFlag SMALLINT,
			@retacctstatus  VARCHAR(2),
			@retpin         VARCHAR(10),
			@retcolstatus   VARCHAR(2),
			@retcustaccid   BIGINT 

	EXEC CISDATA!ValidateCustomerAccount @customer,@account,@lnFlag OUTPUT,@retacctstatus OUTPUT,@retpin OUTPUT,@retcolstatus OUTPUT,@retcustaccid OUTPUT
	IF @lnFlag = 1
		BEGIN
			SET @lcString = 'SELECT TOP '+LTRIM(STR(@Records)) + ' 1 AS RESPONSECODE,SUM(Y_AMOUNT)*-1 AS PAYAMOUNT,D_PAYDATE AS PAYDATE '
					+ ' FROM ADVANCED.BIF956 '
					+ ' WHERE C_CUSTOMER=''' + @customer + ''' AND C_ACCOUNT=''' + @account + ''''
					+ ' AND Y_AMOUNT < 0 AND L_PROCESSED = 1 AND L_DELETED = 0 AND C_TRANSCODE IN  '
					+' (SELECT C_TRANSCODE FROM ADVANCED.GLE001 WHERE C_TRANSCODE LIKE''PA%'') '
					+ ' GROUP BY I_PARENTTR, D_PAYDATE '
					+ ' ORDER BY D_PAYDATE DESC '
			EXEC(@lcString)
		END

	SELECT @rtnvalue = @lnFlag

	IF @lnFlag != 1
		SELECT @lnFlag AS RESPONSECODE, 0 AS PAYAMOUNT, '1900-01-01' AS PAYDATE
RETURN
 
 
--SVN last revision and last change date
--$Revision: 101913 $ $LastChangedDate: 2021-10-21 13:50:23 -0400 (Thu, 21 Oct 2021) $
--$LastChangedDate: 2024-12-17 10:10:00-0400 (Tue, 17 Dec 2024) $