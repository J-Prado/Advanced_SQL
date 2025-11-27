PROCEDURE CISDATA!GETACCOUNTDATA
CREATE PROCEDURE CISDATA!GETACCOUNTDATA           
      @customer   VARCHAR(15),              
      @account    VARCHAR(15),              
      @customerrequired BIT,              
      @phonetypepriority  VARCHAR(20),              
      @recordcontact    BIT,              
      @rtnvalue   INT   OUTPUT,              
      @usebusinessdays  BIT = 0          
AS              
      SET NOCOUNT ON              
      DECLARE @lcstring VARCHAR(50),              
            @lnFlag           SMALLINT,              
            @pin  VARCHAR(10),              
            @currentbalance         DECIMAL(15,2),              
            @accountstatus          VARCHAR(2),              
            @ivrstatus              SMALLINT,              
            @billnumber             BIGINT,              
            @billdate               DATE,              
            @billduedate      DATE,              
            @billamount       DECIMAL(15,2),              
            @pastdueamount    DECIMAL(15,2),              
            @firstname  VARCHAR(100),              
            @lastname   VARCHAR(100),              
            @streetnumber     VARCHAR(10),              
            @streetname VARCHAR(120),              
            @citytown   VARCHAR(25),              
            @stateprov  VARCHAR(2),              
            @zippostal  VARCHAR(15),              
            @paymentamount    DECIMAL(15,2),              
            @paymentdate      DATE,              
            @colstatuscode    VARCHAR(2),              
            @cashonly         BIT,              
            @disconnectdate   DATE,              
            @pendingpayment   DECIMAL(15,2),              
            @paymentplantype  SMALLINT,              
            @drawpayment            BIT,              
            @arrangementamount      DECIMAL(15,2),              
            @arrangementdate        DATE,              
            @arrangementstatus      SMALLINT,              
            @phonenumber      VARCHAR(120),              
            @phonetype  VARCHAR(2),              
            @phonedesc  VARCHAR(15),              
            @lcAcctType VARCHAR(2),              
            @lcBillType VARCHAR(2),              
            @liDays           INT,              
            @ldtmp            DATE,              
            @lnpay          DECIMAL(15,2),              
            @libatch        INT,              
            @libatch1       INT,              
            @lnamount       DECIMAL(15,2),              
            @lnTemp         DECIMAL(15,2),              
            @pos            INT,              
            @lcphonetype    VARCHAR(2),              
            @lcPD           VARCHAR(2),              
            @lcDC           VARCHAR(2),              
            @liGroup        INT,              
            @retcustaccid     BIGINT,              
            @commentcode      VARCHAR(100),              
            @ccycle           VARCHAR(5),                      
            @serviceorder     BIT = 0,                  
            @pastduedate      DATE='',
            @commenttypecode VARCHAR(100),
            @cCode VARCHAR(4),
            @cDisallowPayTypes VARCHAR(200),
            @includeNotice BIT = 0,
            @includePendingforPastdue BIT = 1,
            @tBillCalc  DATETIME,
			@containerName varchar (200)
              
      DECLARE @lcCustomer VARCHAR(15), @lcAccount VARCHAR(15),@lbalinpap003 BIT             
      DECLARE @fullplantype VARCHAR(2),@plantype VARCHAR(1)              
      DECLARE @ybilled  DECIMAL(15,2),@ycredit DECIMAL(15,2),@luseplanbilledamtforprevbill BIT 
      DECLARE @lreconcil BIT, @plancredit DECIMAL(15,2) =0  
      DECLARE @paymentMadeBeforeDueDate DECIMAL(15,2) = 0
      DECLARE @excludeCreditTransCodes varchar(500)  =''
      DECLARE @excludeDebitTransCodes varchar(500)  =''
      DECLARE @excludetransCodes varchar(500), @cTranscode VARCHAR(5) , @balanceTransferCodes varchar(500)='' 

      SELECT @lcCustomer=@customer, @lcAccount=@account              
      SELECT @paymentplantype=0, @lbalinpap003=0, @disconnectdate=''             
      SELECT @currentbalance=0, @luseplanbilledamtforprevbill=0
      SELECT @lreconcil=NULL, @pendingpayment=0, @paymentMadeBeforeDueDate=0

      EXEC CISDATA!VALIDATEACCOUNT @account,@lnFlag OUTPUT              
                    
      IF @lnFlag = 1              
      BEGIN              
            IF @customerrequired = 1              
	 EXEC CISDATA!VALIDATECUSTOMER @customer,@lnFlag OUTPUT              
            ELSE              
               EXEC CISDATA!GETCUSTOMER @account,@lcCustomer OUTPUT,@lnFlag OUTPUT              
              
            IF @lnFlag = 1              
                  EXEC CISDATA!VALIDATECUSTOMERACCOUNT @lcCustomer,@lcAccount,@lnFlag OUTPUT,@accountstatus OUTPUT,@pin OUTPUT,@colstatuscode OUTPUT, @retcustaccid OUTPUT
              
            IF @lnFlag = 1              
           BEGIN              
                        --record contact              
                        IF @recordcontact = 1              
                              EXEC CISDATA!RECORDCONTACT @lcCustomer,@lcAccount,'','','','',0,0,@lnFlag OUTPUT              
              
                        --customer name              
                        SELECT @firstname=C_FIRSTNAME,@lastname=C_LASTNAME FROM CISDATA!BIF001 WHERE C_CUSTOMER=@lcCustomer              
              
                        --service address info              
                        SELECT @streetnumber=ISNULL(CAST(BIF002.N_STREETNUM AS VARCHAR(10)), '')+' '+ISNULL((SELECT C_DESCRIPTION FROM CISDATA!CON151 WHERE C_CODE=C_STRNUMSUFFIX),''),              
                              @streetname=ISNULL((SELECT C_DESCRIPTION FROM CISDATA!CON137 WHERE C_STREETPREFIX = BIF002.C_STREETPREFIX),'')+' '+BIF002.C_STREET+' '+(BIF002.C_STREETSUFFIX)+' '+BIF002.C_APT,
                              @citytown=C_TOWN,@stateprov=C_PROV,@zippostal=C_POSTCODE FROM CISDATA!BIF002               
                              WHERE C_ACCOUNT=@lcAccount              
              
                        --plan type              
                        SET @drawpayment = 0              
                                 
                        DECLARE csrPAP CURSOR FAST_FORWARD FOR               
                        SELECT PAP002.L_DRAW,PAP001.C_PLANTYPE,PAP002.C_TYPE,PAP002.L_USEBALANCEINPAP003,PAP002.L_USEPLANBILLEDAMTFORPREVBILL, PAP002.C_EXCLUDECREDITTRANSCODES, PAP002.C_EXCLUDEDEBITTRANSCODES 
                         FROM CISDATA!PAP001 PAP001 INNER JOIN CISDATA!PAP002 PAP002 ON (PAP001.C_PLANTYPE=PAP002.C_PLANTYPE)                
                        WHERE PAP001.C_CUSTOMER=@lcCustomer AND PAP001.C_ACCOUNT=@lcAccount AND GETDATE()>=PAP001.D_STARTDATE AND (GETDATE()<DATEADD(day,1,PAP001.D_STOPDATE) OR PAP001.D_STOPDATE IS NULL)             
                        OPEN csrPAP              
                        FETCH NEXT FROM csrPAP INTO @drawpayment,@fullplantype,@plantype,@lbalinpap003,@luseplanbilledamtforprevbill, @excludeCreditTransCodes, @excludeDebitTransCodes 
                        IF @@FETCH_STATUS=0
                        BEGIN              
		   IF  @plantype<>'E' AND @plantype<>'L'
			SET @luseplanbilledamtforprevbill = 0
		   IF @plantype='E'              
			SET @paymentplantype = 1              
	       	   IF @plantype='V'              
                                            SET @paymentplantype = 2              
		   IF @plantype='L'              
                                            SET @paymentplantype = 3              
                                IF @plantype IN ('E','L') AND @lbalinpap003=1 
			SELECT @currentbalance=Y_PLANBILLED+Y_CREDITS, @plancredit=Y_CREDITS FROM CISDATA!PAP003 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount
                        END              
                        CLOSE csrPAP              
                        DEALLOCATE csrPAP              

                        --balance in BIF040              
                        IF @lbalinpap003=0              
                              SET @currentbalance = (SELECT SUM(BIF040.Y_CURRENTBALANCE) FROM CISDATA!BIF040 BIF040 INNER JOIN CISDATA!CON091 CON091               
                              ON (BIF040.C_ARCODE=CON091.C_ARCODE)               
                              WHERE BIF040.C_CUSTOMER=@lcCustomer AND BIF040.C_ACCOUNT=@lcAccount AND CON091.L_BIF042=1)               
                       
	         SET @currentbalance = ISNULL(@currentbalance,0)          
              
                        --bill information              
                        SELECT @billdate='',@billduedate='',@billamount=0,@lcAcctType='',@lcBillType='',@lnamount=0              
                        DECLARE csrBIF951 CURSOR FAST_FORWARD FOR              
                        SELECT TOP 1 D_BILLDATE,CASE WHEN D_NEWDUEDATE IS NOT NULL THEN D_NEWDUEDATE ELSE D_DUEDATE END,Y_CURRENTTRANSACTIONS,C_ACCOUNTTYPE,C_BILLTYPE,Y_AMOUNTDUEBEFOREDUEDATE,T_CALC, I_BILLNUMBER FROM CISDATA!BIF951               
                        WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND L_CANCEL=0 AND L_NOBILL=0 AND C_BILLTYPE<>'CB' AND L_PROCESSED=1 ORDER BY D_BILLDATE DESC 
                        open csrBIF951              
                        fetch next from csrBIF951 into @billdate,@billduedate,@billamount,@lcAcctType,@lcBillType,@lnamount, @tBillCalc, @billNumber
                        IF @@fetch_status=0            
                        BEGIN              
                              IF @billduedate IS NOT NULL AND @lcAcctType<>''              
                                    BEGIN              
                                          SELECT @liDays=ISNULL((SELECT SUM(I_DAYS) FROM CISDATA!CON008 WHERE C_ACCOUNTTYPE=@lcAcctType AND C_BILLTYPE=@lcBillType),0)              
                                          IF @usebusinessdays = 1         
                                                SELECT @disconnectdate = CISDATA!GetDisconnectDate(@billduedate, @lcAcctType, @lcBillType)           
                                          ELSE               
                                                SELECT @disconnectdate=DATEADD(day,@liDays,@billduedate)           
                                    END              
		      --Payment made before due date to calculate amount due before due date
        		      SELECT @paymentMadeBeforeDueDate = ISNULL((SELECT SUM(BIF041.Y_AMOUNT) FROM CISDATA!BIF041 WHERE BIF041.C_CUSTOMER = @lcCustomer AND BIF041.C_ACCOUNT = @lcAccount 
			AND T_TRANSDT>=@tBillCalc AND Y_AMOUNT<0 AND (I_BILLNUMBER = 0 AND I_TRANSNUM NOT IN (SELECT I_TRANSNUM FROM CISDATA!BIF955 WHERE C_CUSTOMER = @lcCustomer AND BIF955.C_ACCOUNT = @lcAccount)) 
			AND C_TRANSCODE NOT IN (SELECT C_TRANSCODE FROM CISDATA!GLE001 WHERE C_TRANSACtIONTYPE='AD')),0)
                                    -- payment returned
                	      SET @paymentMadeBeforeDueDate = @paymentMadeBeforeDueDate + ISNULL((SELECT SUM(Y_AMOUNT) FROM CISDATA!BIF041 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount  AND L_STATEMENT=0 
			AND Y_AMOUNT>0 AND T_TRANSDT>=@tBillCalc AND C_TRANSCODE IN (SELECT C_TRANSCODE FROM CISDATA!GLE001 WHERE L_USEORIGINALAGE=1)),0) 
     		      SET  @lnamount = @lnamount + @paymentMadeBeforeDueDate
		      if @lnamount<0
		     	set @lnamount=0
                         END              
                        close csrBIF951              
                        deallocate csrBIF951              

	         SET @pendingpayment=ISNULL((SELECT SUM(Y_AMOUNT) FROM CISDATA!BIF956 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND Y_AMOUNT<0 AND L_PROCESSED=0 AND I_PARENTTR=0 AND I_RECEIPT=0 AND L_DELETED=0 AND C_TRANSCODE IN (SELECT C_TRANSCODE FROM CISDATA!GLE001 WHERE C_TRANSACTIONTYPE='CA')),0)
	         SET @pendingpayment=@pendingpayment+ISNULL((SELECT SUM(Y_AMOUNT) FROM CISDATA!BIF956 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND Y_AMOUNT<0 AND L_PROCESSED=0 AND I_RECEIPT<>0 AND L_DELETED=0 AND C_TRANSCODE IN (SELECT C_TRANSCODE FROM CISDATA!GLE001 WHERE C_TRANSACTIONTYPE='CA')),0)
	         SET @pendingpayment=@pendingpayment+ISNULL((SELECT SUM(Y_AMOUNT) FROM CISDATA!UTL045 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND L_PROCESSED=0),0)
	         SET  @lnamount = @lnamount + @pendingpayment

                        --exclude transcodes 
	         SET @excludetransCodes = ''           
                        DECLARE csrTransCodes CURSOR FAST_FORWARD FOR              
                        SELECT DISTINCT C_CREDITTRANSCODE FROM CISDATA!CON091 WHERE (L_SUMMARY=1 OR L_BIF042=1) UNION SELECT DISTINCT C_DEBITTRANSCODE FROM
			 CISDATA!CON091 WHERE (L_SUMMARY=1 OR L_BIF042=1)
                        open csrTransCodes              
                        fetch next from csrTransCodes into @cTranscode
	         WHILE @@FETCH_STATUS=0
		BEGIN
		       if @cTranscode<>''
			        SET @excludetransCodes = @excludetransCodes + @cTranscode +','
	                       fetch next from csrTransCodes into @cTranscode
		END
         	         close csrTransCodes
	         deallocate csrTransCodes
	         SET @balanceTransferCodes = @excludetransCodes
	         SET @excludetransCodes = @excludetransCodes+@excludeCreditTransCodes+','+@excludeDebitTransCodes+','

                       --Past Due Amount Calculation	

	        SELECT TOP 1 @includeNotice=L_INCLUDEINBALANCEOWING FROM CISDATA!GLE001 WHERE L_INCLUDEINBALANCEOWING =1
	        SELECT TOP 1 @includePendingforPastdue=L_INCLPENDINGPAYMENTFORPASTDUE FROM CISDATA!BIF000

	        SET @pastdueamount = @currentbalance  
    	        --mimic v4 logic to calculate past due amount
    	        DECLARE @isMaster bit, @billGroup VARCHAR(5), @lUpdatetoMaster bit
      	        SELECT @isMaster=A.L_MASTER, @billGroup = A.C_BILLGROUP, @lUpdatetoMaster=B.L_UPDATEBILLTRANSTOMASTER FROM CISDATA!BIF003 A INNER JOIN CISDATA!BIF071 B ON (A.C_BILLGROUP=B.C_BILLGROUP)
		WHERE A.C_CUSTOMER=@lcCustomer AND A.C_ACCOUNT=@lcAccount AND A.L_MASTER=1 AND B.L_UPDATEBILLTRANSTOMASTER=1 ORDER BY A.C_ACCOUNTSTATUS
	        if @isMaster is not null and @isMaster =1 and @lUpdatetoMaster=1
		BEGIN
		SET @lnTemp = ISNULL((SELECT SUM(Y_CURRENTTRANSACTIONS) FROM CISDATA!BIF951 WHERE C_BILLGROUP=@billGroup AND L_MASTER=0 AND L_PROCESSED=1 AND C_BILLTYPE<>'CB' AND D_DUEDATE>=CONVERT(DATE,getdate())),0)
		if  @lnTemp > 0
			set @pastdueamount = @pastdueamount - @lnTemp
		END
	       else
		BEGIN
		IF @luseplanbilledamtforprevbill=1
			BEGIN
			SELECT TOP 1 @lreconcil=L_RECONCIL, @ybilled=Y_PLANBILL, @ycredit=Y_PLANCRED, @billnumber=I_BILLNUMBER FROM CISDATA!BIF951 
				 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND L_CANCEL=0 AND L_NOBILL=0 AND C_BILLTYPE<>'CB' AND L_PROCESSED=1 AND D_DUEDATE>=CONVERT(DATE,getdate()) ORDER BY D_DUEDATE DESC 
			 IF @lreconcil IS NOT NULL
				 BEGIN
				if @lreconcil=1
					SET @pastdueamount = @ybilled + @ycredit + @plancredit
				else
					SET @pastdueamount = @ybilled + @plancredit
				-- adjustments	
				SET @lnTemp = ISNULL((SELECT SUM(N_AMOUNT) FROM CISDATA!BIF955 WHERE I_BILLNUMBER=@billnumber AND C_ACCOUNT=@lcAccount AND L_BIF042=1 AND N_SUMFLAG=0 AND N_AMOUNT>0 AND I_TRANSNUM>0 AND I_ORIGBILL=0 AND CHARINDEX(c_transcode+',',@excludetransCodes)=0),0)
				SET @pastdueamount = @pastdueamount - @lnTemp 
				 END
			END
		ELSE IF @pastdueamount > 0
			BEGIN
			IF @includeNotice=1
				--not due amount
				SET @lnTemp =(SELECT SUM(A.N_AMOUNT) FROM  
					(SELECT N_AMOUNT,I_BILLNUMBER, C_TRANSCODE,L_BIF042,C_ARCODE,N_SUMFLAG FROM CISDATA!BIF955 WHERE 
					C_ACCOUNT =@lcAccount  AND I_ORIGBILL=0 AND I_TRANSNUM>0) A 
					INNER JOIN CISDATA!BIF951 B ON (A.I_BILLNUMBER=B.I_BILLNUMBER) INNER JOIN CISDATA!GLE001 C 
					ON (A.C_TRANSCODE=C.C_TRANSCODE)
					WHERE B.D_DUEDATE>=CONVERT(DATE,getdate()) AND B.L_PROCESSED=1 AND A.N_SUMFLAG<>5 AND 
					(A.L_BIF042=0 OR (A.L_BIF042=1 AND C.C_TRANSACTIONTYPE<>'CA' AND A.N_AMOUNT>0)) 
					AND A.C_ARCODE NOT IN (SELECT C_ARCODE FROM CISDATA!CON091 WHERE L_DEPOSITPAID=1 OR L_DEPOSITINTEREST=1)
					AND A.C_TRANSCODE NOT IN (SELECT B41.C_TRANSCODE FROM CISDATA!BIF041 B41 INNER JOIN CISDATA!GLE001 G01 
					ON (B41.C_TRANSCODE=G01.C_TRANSCODE) WHERE B41.C_CUSTOMER=@lcCustomer AND B41.C_ACCOUNT=@lcAccount AND
					 B41.D_AGING IS NOT NULL AND G01.L_NSFTRANSACTION=1)  
					AND CHARINDEX(A.C_TRANSCODE+',',@balanceTransferCodes)=0)

			ELSE
				-- not due amount
				SET @lnTemp=ISNULL((SELECT SUM(Y_CURRENTTRANSACTIONS) FROM CISDATA!BIF951 WHERE C_CUSTOMER=@lcCustomer AND 
				C_ACCOUNT=@lcAccount AND L_CANCEL=0 AND L_NOBILL=0 AND C_BILLTYPE<>'CB' AND L_PROCESSED=1 
				AND D_DUEDATE>=CONVERT(date,getdate())),0)

			SET @pastdueamount = @pastdueamount - ABS(ISNULL(@lnTemp,0)) 
			END
			-- not billed amount
			IF @includeNotice=1
				SET @lnTemp=(SELECT SUM(BIF041.Y_AMOUNT) FROM CISDATA!BIF041 INNER JOIN CISDATA!GLE001 ON
				 GLE001.C_TRANSCODE=BIF041.C_TRANSCODE  WHERE BIF041.C_CUSTOMER=@lcCustomer AND BIF041.C_ACCOUNT=@lcAccount AND
				T_TRANSDT > DATEADD(month, -12, GETDATE())  AND BIF041.L_STATEMENT = 0 AND Y_AMOUNT > 0 AND D_AGING IS NULL AND
				 GLE001.L_INCLUDEINBALANCEOWING=0 AND ((I_BILLNUMBER = 0 AND (I_LINKEDTRANSNUM = 0 OR (SELECT COUNT(*) FROM 
				CISDATA!BIF955 WHERE BIF041.I_TRANSNUM = BIF955.I_TRANSNUM)=0))  OR (ISNULL((SELECT I_PBILLNUM FROM CISDATA!BIF956
				 WHERE BIF956.I_TRANSNUM = BIF041.I_TRANSNUM),0) = I_BILLNUMBER AND ISNULL((SELECT D_DUEDATE FROM CISDATA!BIF951 
				WHERE BIF041.I_BILLNUMBER = BIF951.I_BILLNUMBER),CONVERT(DATE,getdate()) ) < CONVERT(DATE,getdate()) )) 
				   AND CHARINDEX(BIF041.C_TRANSCODE+',',@excludetransCodes)=0)
			ELSE
				SET @lnTemp=(SELECT SUM(BIF041.Y_AMOUNT) FROM CISDATA!BIF041  WHERE BIF041.C_CUSTOMER=@lcCustomer 
				AND BIF041.C_ACCOUNT=@lcAccount AND
				T_TRANSDT > DATEADD(month, -12, GETDATE())  AND BIF041.L_STATEMENT = 0 AND Y_AMOUNT > 0 AND D_AGING IS NULL 
				 AND ((I_BILLNUMBER = 0 AND (I_LINKEDTRANSNUM = 0 OR (SELECT COUNT(*) FROM 
				CISDATA!BIF955 WHERE BIF041.I_TRANSNUM = BIF955.I_TRANSNUM)=0))  OR (ISNULL((SELECT I_PBILLNUM FROM CISDATA!BIF956
				 WHERE BIF956.I_TRANSNUM = BIF041.I_TRANSNUM),0) = I_BILLNUMBER AND ISNULL((SELECT D_DUEDATE FROM CISDATA!BIF951 
				WHERE BIF041.I_BILLNUMBER = BIF951.I_BILLNUMBER),CONVERT(DATE,getdate()) ) < CONVERT(DATE,getdate()) )) 
				   AND CHARINDEX(BIF041.C_TRANSCODE+',',@excludetransCodes)=0)
			
			SET @pastdueamount = @pastdueamount - ISNULL(@lnTemp,0) 

			-- pending payment 
			IF @includePendingforPastdue=1
				SET @pastdueamount = @pastdueamount + @pendingpayment
									
			if @billdate is null or @billdate=''
				set @ldtmp = CONVERT(date,getdate())
			else
				set @ldtmp = @billdate
			--use the last bill date to get the records in BIF041 that is not part of any bill (i_billnumer=0)

			SET @lnTemp=(SELECT SUM(BIF041.Y_AMOUNT) FROM CISDATA!BIF041 INNER JOIN CISDATA!GLE001 ON 
				(BIF041.C_TRANSCODE=GLE001.C_TRANSCODE) 
				 WHERE BIF041.C_CUSTOMER = @lcCustomer  AND BIF041.C_ACCOUNT = @lcAccount AND T_TRANSDT > @ldtmp  
				AND Y_AMOUNT > 0 AND D_AGING IS NULL AND GLE001.L_NSFTRANSACTION =1 )

			SET @pastdueamount = @pastdueamount - ISNULL(@lnTemp,0)

		END

	              IF @pastdueamount<0                              
			SET @pastdueamount=0 
  	              ELSE                              
		      BEGIN                              
		             SELECT @ldtmp=(SELECT TOP 1 D_DUEDATE FROM CISDATA!BIF951 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND D_DUEDATE<CONVERT(DATE,getdate()) AND L_CANCEL=0 AND L_NOBILL=0 AND C_BILLTYPE<>'CB' AND L_PROCESSED=1              
				ORDER BY D_BILLDATE DESC)               
		              IF @ldtmp IS NOT NULL                               
    				SET @pastduedate=@ldtmp 
 		    END                              
               
	         --Payment info              
                        select @paymentamount=0,@paymentdate=''              
                        declare csrBIF956 CURSOR FAST_FORWARD for               
                        SELECT Y_AMOUNT,I_BATCHID,D_PAYDATE FROM CISDATA!BIF956               
                        WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount AND Y_AMOUNT<0 AND L_PROCESSED=1 AND L_DELETED=0               
                        AND C_ARCODE<>'' AND I_BATCHID IN (SELECT I_BATCHID FROM CISDATA!BIF503 WHERE C_TRANSACTIONTYPE = 'CA')              
						AND C_TRANSCODE NOT IN (SELECT DISTINCT C_DEPOSITPAIDTRANSCODE FROM ADVANCED.CON103)
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
		            
                        --Cash only    
	         SET @cashonly=0
                        IF EXISTS(SELECT TOP 1 A.I_BIF017PK FROM CISDATA!BIF017 A INNER JOIN CISDATA!CON081 B ON (A.C_COMMENTCODE=B.C_COMMENTCODE) WHERE A.C_ACCOUNT=@lcAccount AND B.L_CASHONLY=1 AND B.C_TYPE='A' 
			AND (A.D_EXPIRATIONDATE IS NULL OR  GETDATE()<DATEADD(day,1,A.D_EXPIRATIONDATE))) 
                              SET @cashonly=1              
                        ELSE IF EXISTS(SELECT TOP 1 A.I_BIF017PK FROM CISDATA!BIF017 A INNER JOIN CISDATA!CON081 B ON (A.C_COMMENTCODE=B.C_COMMENTCODE) WHERE A.C_CUSTOMER=@lcCustomer AND B.L_CASHONLY=1 
			AND (A.D_EXPIRATIONDATE IS NULL OR GETDATE()< DATEADD(day,1,A.D_EXPIRATIONDATE))) 
                              SET @cashonly=1              

	         --COMMENT TYPE CODE 
			 
	         SELECT @commenttypecode='',@cDisallowPayTypes='',@commentcode=''
                        DECLARE csrbif017 CURSOR FAST_FORWARD FOR
		SELECT DISTINCT A.C_COMMENTCODE, B.C_DISALLOWEDPAYMENTTYPES FROM CISDATA!BIF017 A INNER JOIN CISDATA!CON081 B ON (A.C_COMMENTCODE=B.C_COMMENTCODE) 
			WHERE (A.C_CUSTOMER=@lcCustomer OR  A.C_ACCOUNT=@account) AND (A.D_EXPIRATIONDATE IS NULL OR GETDATE()<DATEADD(DAY,1,A.D_EXPIRATIONDATE))
	         open csrBIF017              
	         fetch next from csrBIF017 into @cCode,@lcstring 
	         WHILE @@FETCH_STATUS=0
			BEGIN
				SET @commenttypecode = @commenttypecode+@cCode+','
				SET @cDisallowPayTypes = @cDisallowPayTypes+@lcstring+','
		              		fetch next from csrBIF017 into @cCode,@lcstring 
			END
	          close csrBIF017
	          deallocate csrBIF017

          	    	--COMMENT CODE	
					Declare @containerNameString varchar(200)
					Select @containerName='', @containerNameString=''
                        DECLARE csrCON082 CURSOR FAST_FORWARD FOR
		SELECT C_PAYMENTTYPE, C_CONTAINERNAME FROM CISDATA!CON082 WHERE CHARINDEX(C_CODE,@cDisallowPayTypes)=0 
	         open csrCON082             
	         fetch next from csrCON082 into @lcstring , @containerNameString
	         WHILE @@FETCH_STATUS=0
			BEGIN
				SET @commentcode = @commentcode+@lcstring+','
				Set @containerName = @containerName + @containerNameString + ',' 
		              		fetch next from csrCON082 into @lcstring , @containerNameString
			END
	          close csrCON082
	          deallocate csrCON082

		--CCycle              
	         SET @ccycle = (SELECT TOP 1 C_CYCLE FROM CISDATA!BIF003 WHERE C_CUSTOMER =@lccustomer and C_ACCOUNT =@lcaccount ORDER BY D_EFFECTIVEDATE DESC) 
           
           	             --Service Order              
	         IF EXISTS(SELECT 1 FROM CISDATA!BIF023 WHERE C_CUSTOMER = @lccustomer and C_ACCOUNT = @lcaccount AND L_CANCELLED =0 and L_COMPLETED = 0)              
		         SET @serviceorder = 1              
                          
                        --Phone type parse              
                        SELECT @phonetype='', @phonenumber='', @phonedesc=''

                        SET @lcstring=ltrim(rtrim(@phonetypepriority))
                        if right(@lcstring,1) <> ','              
                              set @lcstring = @lcstring + ','              
                        set @pos =  patindex('%,%' , @lcstring)              
                        while @pos <> 0               
                              begin
                                    set @lcphonetype = left(@lcstring,@pos-1)              
                                    select top 1 @phonenumber=A.C_PHONENUMBER,@phonetype= A.C_PHONETYPE,@phonedesc=B.C_DESCRIPTION               
                                               FROM CISDATA!BIF010 A INNER JOIN CISDATA!CON014 B ON (A.C_PHONETYPE=B.C_PHONETYPE)               
                                                WHERE C_CUSTOMER=@lcCustomer AND A.C_PHONETYPE=@lcphonetype AND A.C_ADDTYPE=' '              
                                      if @phonenumber<>''              
                                          break;              
              
                                    set @lcstring = stuff(@lcstring, 1, @pos, '')              
                                    set @pos = patindex('%,%' , @lcstring)              
                              end              

                        --arrangment              
                        SELECT @arrangementamount=0,@arrangementdate='',@arrangementstatus=0,@liGroup=0              
                        SELECT TOP 1 @arrangementamount=Y_AMOUNT,@arrangementdate=D_ARRANGE,@arrangementstatus=(CASE WHEN C_STATUS='N' THEN 1 WHEN C_STATUS='B' THEN 2 WHEN C_STATUS='K' THEN 3              
                                    WHEN C_STATUS='P' THEN 4 ELSE 5 END), @liGroup=I_GROUP FROM CISDATA!BIF007 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount              
                                    ORDER BY D_ARRANGE DESC              
              
                        if @liGroup > 0 AND @arrangementdate>getdate()-1       -- if group, return the first one       
	                 SELECT TOP 1 @arrangementamount=Y_AMOUNT,@arrangementdate=D_ARRANGE,@arrangementstatus=(CASE WHEN C_STATUS='N' THEN 1 WHEN C_STATUS='B' THEN 2 WHEN C_STATUS='K' THEN 3              
                                    WHEN C_STATUS='P' THEN 4 ELSE 5 END) FROM CISDATA!BIF007 WHERE C_CUSTOMER=@lcCustomer AND C_ACCOUNT=@lcAccount  AND I_GROUP=@liGroup AND D_ARRANGE >=Convert(date,getdate())              
                                    ORDER BY D_ARRANGE ASC              
              
                        SET @ivrstatus = 5              
                        if @accountstatus='AC' AND @pastdueamount=0              
                              SET @ivrstatus = 1              
                        if @ivrstatus=5 AND @accountstatus<>'AC'              
                              SET @ivrstatus = 2              
                        if @ivrstatus=5 AND @accountstatus='AC' 
		BEGIN
                       	 --check pending disconnect and disconnected collection status code              
                        	set @lcPD=(SELECT TOP 1 C_PENDINGDISCONNECTSTATUS FROM CISDATA!COL109 WHERE C_PENDINGDISCONNECTSTATUS<>'')              
                        	set @lcDC=(SELECT TOP 1  C_DISCONNECTSTATUS FROM CISDATA!COL109 WHERE C_DISCONNECTSTATUS<>'')              
		if  @colstatuscode=@lcPD           
	                              SET @ivrstatus = 3
		if @colstatuscode=@lcDC              
                             		SET @ivrstatus = 4              
		END

            SET @billNumber = ISNULL(@billNumber,0)
              
                       SELECT       @lcCustomer AS CUSTOMER,               
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
                                    @commentcode  AS COMMENTCODE,              
                                    @ccycle  as CYCLE,              
                                    @serviceorder as SERVICEORDER,              
                                    @pastduedate as PASTDUEDATE,
						@lnamount AS AMOUNTDUEBEFOREDUEDATE,  
						@commenttypecode  AS COMMENTTYPECODE,
						@containerName AS CONTAINERNAME,
                                    @billNumber AS BILLNUMBER,
                                    @lnFlag AS RESPONSECODE                                    
      	END              
      END              
      SELECT @rtnvalue = @lnFlag              
RETURN 
 
 
--SVN last revision and last change date
--$Revision: 88421 $ $LastChangedDate: 2020-09-24 10:00:33 -0400 (Thu, 24 Sep 2020) $
