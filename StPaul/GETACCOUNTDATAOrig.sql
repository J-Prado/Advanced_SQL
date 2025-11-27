PROCEDURE CISDATA!GETACCOUNTDATA
CREATE PROCEDURE CISDATA!GETACCOUNTDATA
	@customer	VARCHAR(15),
	@account	VARCHAR(15),
	@customerrequired	BIT,
	@phonetypepriority	VARCHAR(20),
	@recordcontact	BIT,
	@rtnvalue	INT	OUTPUT,
	@usebusinessdays	BIT = 0
AS
	SET NOCOUNT ON
	DECLARE @lcstring	VARCHAR(20),
		@lnFlag		SMALLINT,
		@outcustomer	VARCHAR(15),
		@pin	VARCHAR(10),
		@currentbalance		DECIMAL(15,2),
		@accountstatus		VARCHAR(2),
		@ivrstatus			SMALLINT,
		@billnumber	BIGINT,
		@billdate	DATE,
		@billduedate	DATE,
		@billamount	DECIMAL(15,2),
		@pastdueamount	DECIMAL(15,2),
		@firstname	VARCHAR(100),
		@lastname	VARCHAR(100),
		@streetnumber	VARCHAR(10),
		@streetname	VARCHAR(90),
		@citytown	VARCHAR(25),
		@stateprov	VARCHAR(2),
		@zippostal	VARCHAR(10),
		@paymentamount	DECIMAL(15,2),
		@paymentdate	DATE,
		@colstatuscode	VARCHAR(2),
		@cashonly	BIT,
		@disconnectdate	DATE,
		@pendingpayment	DECIMAL(15,2),
		@paymentplantype	SMALLINT,
		@drawpayment		BIT,
		@arrangementamount	DECIMAL(15,2),
		@arrangementdate	DATE,
		@arrangementstatus	SMALLINT,
		@phonenumber	VARCHAR(20),
		@firsttype	VARCHAR(2),
		@phonetype	VARCHAR(2),
		@phonedesc	VARCHAR(15),
		@rtnvalue2	SMALLINT,
		@lcAcctType	VARCHAR(2),
		@lcBillType	VARCHAR(2),
		@liDays		INT,
		@ldtmp		DATE,
		@lnpay          DECIMAL(15,2),
		@libatch        INT,
		@libatch1       INT,
		@lnpending      DECIMAL(15,2),
		@lipk           BIGINT,
		@lnamount       DECIMAL(15,2),
		@lnadjustments  DECIMAL(15,2),
		@pos            INT,
		@lcphonetype    VARCHAR(2),
		@lcphone        VARCHAR(100),
		@lcPD           VARCHAR(2),
		@lcDC           VARCHAR(2),
		@liGroup        INT,
		@retcustaccid	BIGINT,
		@commentcode	VARCHAR(100),
		@rtnvalue3		SMALLINT

	DECLARE @lcCustomer VARCHAR(15), @lcAccount VARCHAR(15),@lbalinpap003 SMALLINT,@ldraw BIT
	DECLARE @fullplantype VARCHAR(2),@plantype VARCHAR(1),@dstart DATE,@dstop DATE
	DECLARE @lbalinplan SMALLINT,@ybilled  DECIMAL(15,2),@ycredit DECIMAL(15,2)

	SELECT @lcCustomer=@customer, @lcAccount=@account, @lcstring=@phonetypepriority
	SELECT @paymentplantype=0,@lbalinpap003=0,@disconnectdate='',@lbalinplan=0

	EXEC CISDATA!VALIDATEACCOUNT @account,@lnFlag OUTPUT
	
	IF @lnFlag = 1
	BEGIN
		IF @customerrequired = 1
			EXEC CISDATA!VALIDATECUSTOMER @customer,@lnFlag OUTPUT
		ELSE
			EXEC CISDATA!GETCUSTOMER @account,@lcCustomer OUTPUT,@lnFlag OUTPUT

		IF @lnFlag = 1
		BEGIN
			EXEC CISDATA!VALIDATECUSTOMERACCOUNT @lcCustomer,@lcAccount,@lnFlag OUTPUT,@accountstatus OUTPUT,@pin OUTPUT,@colstatuscode OUTPUT, @retcustaccid OUTPUT

			IF @lnFlag = 1
			BEGIN
				SELECT @outcustomer=@lcCustomer
				--check pending disconnect and disconnected collection status code
				set @lcPD=(SELECT TOP 1 C_PENDINGDISCONNECTSTATUS FROM CISDATA!COL109 WHERE C_PENDINGDISCONNECTSTATUS<>'')
				set @lcDC=(SELECT TOP 1  C_DISCONNECTSTATUS FROM CISDATA!COL109 WHERE C_DISCONNECTSTATUS<>'')
				--record contact
				IF @recordcontact = 1
					EXEC CISDATA!RECORDCONTACT @lcCustomer,@lcAccount,'','','','',0,0,@rtnvalue3 OUTPUT

				--customer name
				select @firstname='',@lastname=''
				SELECT @firstname=C_FIRSTNAME,@lastname=C_LASTNAME FROM CISDATA!BIF001 WHERE C_CUSTOMER=@lcCustomer

				--service address info
				SELECT @streetnumber='',@streetname='',@citytown='',@stateprov='',@zippostal=''
				SELECT @streetnumber=C_STREETNUM+' '+ISNULL((SELECT C_DESCRIPTION FROM CISDATA!CON151 WHERE C_CODE=C_STRNUMSUFFIX),''),
					@streetname=BIF002.C_STREETPREFIX+' '+BIF002.C_STREET+' '+BIF002.C_STREETSUFFIX+' '+BIF002.C_APT,
					@citytown=C_TOWN,@stateprov=C_PROV,@zippostal=C_POSTCODE FROM CISDATA!BIF002 
					WHERE C_ACCOUNT=@lcAccount

				--plan type
				SET @drawpayment = 0
				
				DECLARE csrPAP CURSOR FAST_FORWARD FOR 
				SELECT PAP002.L_DRAW,PAP001.C_PLANTYPE,PAP002.C_TYPE,PAP001.D_STARTDATE,PAP001.D_STOPDATE,PAP002.L_USEBALANCEINPAP003 
				 FROM CISDATA!PAP001 PAP001 INNER JOIN CISDATA!PAP002 PAP002 ON (PAP001.C_PLANTYPE=PAP002.C_PLANTYPE)  
				WHERE PAP001.C_CUSTOMER=@lcCustomer AND PAP001.C_ACCOUNT=@lcAccount
				OPEN csrPAP
				FETCH NEXT FROM csrPAP INTO @ldraw,@fullplantype,@plantype,@dstart,@dstop,@lbalinplan
				WHILE @@FETCH_STATUS=0
				BEGIN
					IF GETDATE()>=@dstart AND (GETDATE()<DATEADD(day,1,@dstop) OR @dstop IS NULL)
						BEGIN
						SET @drawpayment = @ldraw
						IF @plantype='E'
							SET @paymentplantype = 1
						IF @plantype='V'
							SET @paymentplantype = 2
						IF @plantype='L'
							SET @paymentplantype = 3
						IF @fullplantype IN ('EN','LN') AND @lbalinplan=1
								BEGIN
								SET @currentbalance=(SELECT Y_PLANBILLED+Y_CREDITS FROM CISDATA!PAP003 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount)
								SET @lbalinpap003=1
								END
						END
					FETCH NEXT FROM csrPAP INTO @ldraw,@fullplantype,@plantype,@dstart,@dstop,@lbalinplan
				END
				CLOSE csrPAP
				DEALLOCATE csrPAP

				--balance in BIF040
				IF @lbalinpap003=0
					SET @currentbalance = (SELECT SUM(BIF040.Y_CURRENTBALANCE) FROM CISDATA!BIF040 BIF040 INNER JOIN CISDATA!CON091 CON091 
					ON (BIF040.C_ARCODE=CON091.C_ARCODE) 
					WHERE BIF040.C_CUSTOMER=@lcCustomer AND BIF040.C_ACCOUNT=@lcAccount AND CON091.L_BIF042=1)
				SET @currentbalance = ISNULL(@currentbalance,0)

				--Pending payment 
				set @pendingpayment=0
				select @lnpending=(SELECT SUM(Y_AMOUNT) FROM CISDATA!UTL045 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND L_PROCESSED=0)
				if @lnpending IS NULL
					select @lnpending=0.00
				select  @pendingpayment=@lnpending
				select @lnpending=(SELECT SUM(Y_AMOUNT) FROM CISDATA!BIF956 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND Y_AMOUNT<0 AND L_PROCESSED=0 AND I_PARENTTR=0 AND L_DELETED=0)
				if @lnpending IS NULL
					select @lnpending=0.00
				select  @pendingpayment=@pendingpayment+@lnpending

				--bill information
				DECLARE csrBIF951 CURSOR FAST_FORWARD FOR
				SELECT TOP 1 D_BILLDATE,D_DUEDATE,Y_CURRENTTRANSACTIONS,C_ACCOUNTTYPE,C_BILLTYPE,I_BILLNUMBER,Y_AMOUNTDUEBEFOREDUEDATE FROM CISDATA!BIF951 
				WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND L_CANCEL=0 AND L_NOBILL=0 AND C_BILLTYPE<>'CB' AND L_PROCESSED=1 ORDER BY D_BILLDATE DESC
				open csrBIF951
				fetch next from csrBIF951 into @billdate,@billduedate,@billamount,@lcAcctType,@lcBillType,@billnumber,@lnamount
				IF @@fetch_status<>0
					SELECT @billdate='',@billduedate='',@billamount=0,@lcAcctType='',@lcBillType='',@billnumber=0,@lnamount=0
				ELSE
					BEGIN
					IF @billduedate IS NOT NULL AND @lcAcctType<>''
						BEGIN
							SELECT @liDays=ISNULL((SELECT SUM(I_DAYS) FROM CISDATA!CON008 WHERE C_ACCOUNTTYPE=@lcAcctType AND C_BILLTYPE=@lcBillType),0)
							IF @usebusinessdays = 1
								SELECT @disconnectdate = CISDATA!GetDisconnectDate(@billduedate, @lcAcctType, @lcBillType)		-- 06/19/2015 - skips weekends and holidays
							ELSE 
								SELECT @disconnectdate=DATEADD(day,@liDays,@billduedate)
						END
					END
				close csrBIF951
				deallocate csrBIF951
	
				--ID 03/14/14 get sum of cash transactions in the bill not due
 				SELECT @lnadjustments=ISNULL((SELECT SUM(N_AMOUNT) FROM CISDATA!BIF955 WHERE I_BILLNUMBER=@billnumber AND L_BIF042=1 AND N_SUMFLAG=0 AND I_TRANSNUM>0 AND N_AMOUNT>0 AND C_TRANSCODE NOT IN (SELECT C_TRANSCODE FROM CISDATA!GLE001 WHERE L_INCLUDEINBALANCEOWING=1)),0)
				--ID 03/14/14 - end
				
				SELECT @pastdueamount=@currentbalance
				IF getdate()<(DATEADD(day,1,@billduedate))
					SET @pastdueamount=@pastdueamount-@billamount-@lnadjustments

				IF @pastdueamount<=0
					SELECT @pastdueamount=0
				ELSE
					BEGIN
						SELECT @lnamount=ISNULL((SELECT SUM(Y_AMOUNT) 
							FROM CISDATA!BIF041 
							WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND Y_AMOUNT>0 
							AND (I_BILLNUMBER<=0 OR (SELECT COUNT(*) FROM CISDATA!BIF955 WHERE BIF041.I_BILLNUMBER = BIF955.I_BILLNUMBER AND BIF041.I_TRANSNUM = BIF955.I_TRANSNUM)=0)
							AND T_TRANSDT>@billdate
							AND L_STATEMENT=0
							AND C_TRANSCODE NOT IN (SELECT C_TRANSCODE FROM CISDATA!GLE001 WHERE L_INCLUDEINBALANCEOWING=1)),0)
						SELECT @pastdueamount=@pastdueamount-@lnamount
						IF @pastdueamount<=0
							SELECT @pastdueamount=0
						ELSE
							BEGIN
								SELECT @ldtmp=(SELECT TOP 1 D_DUEDATE FROM CISDATA!BIF951 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND D_DUEDATE<getdate() AND L_CANCEL=0 AND L_NOBILL=0 AND C_BILLTYPE<>'CB' AND L_PROCESSED=1 ORDER BY D_BILLDATE DESC)
								IF @ldtmp IS NOT NULL
									select @billduedate=@ldtmp
							END
					END	


				--Payment info
				select @paymentamount=0,@paymentdate=''
				declare csrBIF956 CURSOR FAST_FORWARD for 
				SELECT Y_AMOUNT,I_BATCHID,D_PAYDATE FROM CISDATA!BIF956 
				WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND Y_AMOUNT<0 AND L_PROCESSED=1 AND L_DELETED=0 
				AND C_ARCODE<>'' AND I_BATCHID IN (SELECT I_BATCHID FROM CISDATA!BIF503 WHERE C_TRANSACTIONTYPE = 'CA')
				ORDER BY D_PAYDATE DESC

				open csrBIF956
				fetch next from csrBIF956 into @lnpay,@libatch,@paymentdate
				while @@fetch_status=0
				begin
					If @libatch=-1
						BEGIN
						set @paymentamount=(SELECT SUM(Y_AMOUNT) FROM CISDATA!BIF956 WHERE C_CUSTOMER=@lcCustomer 
							AND C_ACCOUNT=@lcAccount AND Y_AMOUNT<0 AND L_PROCESSED=1 AND L_DELETED=0 AND D_PAYDATE=@paymentdate)
							BREAK
						END
					Else
						BEGIN
						select @paymentamount=@paymentamount+@lnpay
						fetch next from csrBIF956 into @lnpay,@libatch1,@ldtmp
						if @libatch<>@libatch1
							break
						END
				end
				close csrBIF956
				deallocate csrBIF956
				
				SELECT @rtnvalue2 = 1

				--Cash only 
				SET @lipk=(SELECT TOP 1 A.I_BIF017PK FROM CISDATA!BIF017 A INNER JOIN CISDATA!CON081 B ON (A.C_COMMENTCODE=B.C_COMMENTCODE) WHERE A.C_ACCOUNT=@lcAccount AND B.L_CASHONLY=1 AND B.C_TYPE='A' AND (A.D_EXPIRATIONDATE IS NULL OR GETDATE()<DATEADD(day,1,A.D_EXPIRATIONDATE)))
				IF (@lipk IS NOT NULL) AND @lipk>0
					set @cashonly=1
				ELSE
					BEGIN
					SET @lipk=(SELECT TOP 1 A.I_BIF017PK FROM CISDATA!BIF017 A INNER JOIN CISDATA!CON081 B ON (A.C_COMMENTCODE=B.C_COMMENTCODE) WHERE A.C_CUSTOMER=@lcCustomer AND B.L_CASHONLY=1 AND (A.D_EXPIRATIONDATE IS NULL OR GETDATE()<DATEADD(day,1,A.D_EXPIRATIONDATE)))
					IF (@lipk IS NOT NULL) AND @lipk>0
						set @cashonly=1
					ELSE
						set @cashonly=0
					END
				
				SET @commentcode =(SELECT TOP 1 isnull((select c_paymenttype+',' from CISDATA!CON082 where not charindex(CON082.c_code,b.C_DISALLOWEDPAYMENTTYPES)>0 and c_paymenttype<>'' for XML raw(''),elements),'')
									FROM CISDATA!BIF017 A INNER JOIN CISDATA!CON081 B ON (A.C_COMMENTCODE=B.C_COMMENTCODE)
									WHERE A.C_ACCOUNT=@account AND B.L_CASHONLY=0 AND (A.D_EXPIRATIONDATE IS NULL OR GETDATE()<DATEADD(day, 1,A.D_EXPIRATIONDATE)))

				IF (@commentcode is null OR @commentcode ='')
					SET @commentcode = (SELECT TOP 1 isnull((select c_paymenttype+',' from CISDATA!CON082 where not charindex(CON082.c_code,b.C_DISALLOWEDPAYMENTTYPES)>0 and c_paymenttype<>'' for XML raw(''),elements),'')
										FROM CISDATA!BIF017 A INNER JOIN CISDATA!CON081 B ON (A.C_COMMENTCODE=B.C_COMMENTCODE)
										WHERE A.C_CUSTOMER=@lcCustomer AND B.L_CASHONLY=0 AND (A.D_EXPIRATIONDATE IS NULL OR GETDATE()<DATEADD(day,1,A.D_EXPIRATIONDATE)))

				--Phone type parse
				set @lcphone=''
				if right(rtrim(@lcstring),1) <> ','
					 set @lcstring = rtrim(@lcstring) + ','
				set @pos =  patindex('%,%' , @lcstring)
				set @firstType = ' '
				while @pos <> 0 
					begin
						 set @lcphone=''
						 set @lcphonetype = left(@lcstring,@pos-1)

						 if @firstType = ' '
						 begin
							 set @firstType = left(@lcstring,@pos-1)
						 end

						 set @lcphone=(SELECT TOP 1 A.C_PHONETYPE+'|'+RIGHT('                    '+ A.C_PHONENUMBER, 20) +'|'+B.C_DESCRIPTION+'|' 
								FROM CISDATA!BIF010 A INNER JOIN CISDATA!CON014 B ON (A.C_PHONETYPE=B.C_PHONETYPE) 
								WHERE (C_CUSTOMER=@lcCustomer) AND A.C_PHONETYPE=@lcphonetype AND A.C_ADDTYPE=' ')
						 if @lcphone<>''
								break
						 set @lcstring = stuff(@lcstring, 1, @pos, '')
						 set @pos = patindex('%,%' , @lcstring)
					end

				if @lcphone<>''
					select @phonetype=left(@lcphone,2),@phonenumber=LTRIM(RTRIM(SUBSTRING(@lcphone,4,20))),@phonedesc=LTRIM(RTRIM(SUBSTRING(@lcphone,25,15)))
				else
					select @phonetype=@firstType,@phonenumber='',@phonedesc=''

				--arrangment
				set @liGroup = 0
				DECLARE csrBIF007 CURSOR FAST_FORWARD for 
					SELECT TOP 1 Y_AMOUNT,D_ARRANGE,CASE WHEN C_STATUS='N' THEN '1' WHEN C_STATUS='B' THEN '2' WHEN C_STATUS='K' THEN '3'
						WHEN C_STATUS='P' THEN '4' ELSE '5' END AS C_STATUS, I_GROUP FROM CISDATA!BIF007 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount
						ORDER BY D_ARRANGE DESC
				open csrBIF007
				fetch next from csrBIF007 INTO @arrangementamount,@arrangementdate,@arrangementstatus,@liGroup
				IF @@fetch_status<>0
					select @arrangementamount=0,@arrangementdate='',@arrangementstatus=0,@liGroup=0

				close csrBIF007
				deallocate csrBIF007

				--KY 2014-01-13 added to return the close arrangement if group arrangement made, SW#87383
				if @liGroup > 0 AND @arrangementdate>getdate()-1
				BEGIN
					DECLARE csrBIF007 CURSOR FAST_FORWARD for 
					SELECT Y_AMOUNT,D_ARRANGE,CASE WHEN C_STATUS='N' THEN '1' WHEN C_STATUS='B' THEN '2' WHEN C_STATUS='K' THEN '3'
						WHEN C_STATUS='P' THEN '4' ELSE '5' END AS C_STATUS FROM CISDATA!BIF007 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND I_GROUP=@liGroup 
						ORDER BY D_ARRANGE ASC
					open csrBIF007
					fetch next from csrBIF007 INTO @arrangementamount,@arrangementdate,@arrangementstatus
					while @@fetch_status=0
					BEGIN
						if @arrangementdate>getdate()-1
							break
						else
							fetch next from csrBIF007 INTO @arrangementamount,@arrangementdate,@arrangementstatus
					END
					close csrBIF007
					deallocate csrBIF007
				END		

				SELECT @ivrstatus	= 5
				if @accountstatus='AC' AND @pastdueamount=0
					SELECT @ivrstatus = 1
				if @ivrstatus=5 AND @accountstatus<>'AC'
					SELECT @ivrstatus = 2
				if @ivrstatus=5 AND @accountstatus='AC' AND @colstatuscode=@lcPD
					SELECT @ivrstatus = 3
				if @ivrstatus=5 AND @accountstatus='AC' AND @colstatuscode=@lcDC
					SELECT @ivrstatus = 4
				--if @ivrstatus=0 AND @accountstatus='AC' AND @pastdueamount>0 AND (@colstatuscode<>@lcPD AND @colstatuscode<>@lcDC)
				---	SELECT @ivrstatus = 5

				SELECT	@outcustomer AS CUSTOMER, 
						@pin AS PIN, 
						@currentbalance AS CURRENTBALANCE, 
						@accountstatus AS ACCOUNTSTATUS,
						@ivrstatus AS IVRSTATUS,
						@billdate AS BILLDATE,
						@billduedate AS BILLDUEDATE,
						@billamount AS BILLAMOUNT,
						@pastdueamount AS PASTDUEAMOUNT,
						@firstname AS FIRSTNAME,
						@lastname AS LASTNAME,
						@streetnumber AS STREETNUMBER,
						@streetname AS STREETNAME,
						@citytown AS CITYTOWN,
						@stateprov AS STATEPROV,
						@zippostal AS ZIPPOSTAL,
						@paymentamount AS PAYMENTAMOUNT,
						@paymentdate AS PAYMENTDATE,
						@colstatuscode AS COLSTATUSCODE,
						@cashonly AS CASHONLY,
						@disconnectdate AS DISCONNECTDATE,
						@pendingpayment AS PENDINGPAYMENT,
						@paymentplantype AS PAYMENTPLANTYPE,
						@drawpayment AS DRAWPAYMENT,
						@arrangementamount AS ARRANGEMENTAMOUNT,
						@arrangementdate AS ARRANGEMENTDATE,
						@arrangementstatus AS ARRANGEMENTSTATUS,
						@phonenumber AS PHONENUMBER,
						@phonetype AS PHONETYPE,
						@phonedesc AS PHONEDESC,
						@rtnvalue2 AS RESPONSECODE,
						@commentcode  AS COMMENTCODE
			END
		END
	END
	SELECT @rtnvalue = @lnFlag
RETURN
