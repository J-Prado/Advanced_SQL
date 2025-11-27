SET NOCOUNT ON;

DECLARE 
    @TableName      SYSNAME,
    @IndexName      SYSNAME,
    @Frag           DECIMAL(5,2),
    @MaxFrag        DECIMAL(5,2) = 20.0,
    @SchemaName     SYSNAME = 'ADVANCED',
    @SqlVersion     VARCHAR(500) = @@VERSION,
    @SqlCmd         NVARCHAR(600),
    @ActionDesc     VARCHAR(40),
    @ActionCmd      VARCHAR(80),
    @RequiresUpdate BIT = 0;

BEGIN
    PRINT 'Starting index maintenance...';
    PRINT 'Schema: ' + @SchemaName;
    PRINT 'Max Fragmentation Allowed: ' + CAST(@MaxFrag AS VARCHAR(10));
    PRINT 'SQL Version: ' + @SqlVersion;
    PRINT '--------------------------------------------';

    ----------------------------------------------------
    -- Determine whether REORGANIZE or REBUILD ONLINE
    ----------------------------------------------------
    IF CHARINDEX('Enterprise', @SqlVersion) > 0
    BEGIN
        SET @ActionDesc = 'Rebuilding index';
        SET @ActionCmd  = ' REBUILD WITH (ONLINE = ON)';
    END
    ELSE
    BEGIN
        SET @ActionDesc = 'Reorganizing index';
        SET @ActionCmd  = ' REORGANIZE';
        SET @RequiresUpdate = 1;
    END

    ----------------------------------------------------
    -- Cursor for indexes requiring maintenance
    ----------------------------------------------------
    DECLARE IndexCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT 
        OBJECT_NAME(ps.object_id) AS TableName,
        i.name AS IndexName,
        ps.avg_fragmentation_in_percent AS AvgFrag
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, NULL) AS ps
    INNER JOIN sys.indexes AS i 
        ON ps.object_id = i.object_id AND ps.index_id = i.index_id
    INNER JOIN sys.tables AS t
        ON ps.object_id = t.object_id
    WHERE 
        ps.index_id > 0
        AND ps.avg_fragmentation_in_percent > @MaxFrag
        AND SCHEMA_NAME(t.schema_id) = @SchemaName
        AND OBJECT_NAME(ps.object_id) NOT LIKE 'T[0-9]%'  
    ORDER BY TableName, IndexName;

    OPEN IndexCursor;

    FETCH NEXT FROM IndexCursor INTO @TableName, @IndexName, @Frag;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT @ActionDesc + ' ' + @TableName + '.' + @IndexName 
              + ' (Fragmentation: ' + CAST(@Frag AS VARCHAR(10)) + '%)';

        SET @SqlCmd = 
            N'ALTER INDEX ' + QUOTENAME(@IndexName) 
            + N' ON ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName)
            + @ActionCmd;

        BEGIN TRY
            EXEC (@SqlCmd);
        END TRY
        BEGIN CATCH
            PRINT 'ERROR processing ' + @TableName + '.' + @IndexName 
                + ': ' + ERROR_MESSAGE();
        END CATCH;

        FETCH NEXT FROM IndexCursor INTO @TableName, @IndexName, @Frag;
    END

    CLOSE IndexCursor;
    DEALLOCATE IndexCursor;

    ----------------------------------------------------
    -- If reorganize was used, update statistics
    ----------------------------------------------------
    IF @RequiresUpdate = 1
    BEGIN
        PRINT 'Reorganize was used → Updating statistics...';

        DECLARE TableCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT OBJECT_NAME(object_id) AS TableName
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, NULL) AS ps
        INNER JOIN sys.tables AS t ON ps.object_id = t.object_id
        WHERE 
            ps.avg_fragmentation_in_percent > @MaxFrag
            AND SCHEMA_NAME(t.schema_id) = @SchemaName
            AND OBJECT_NAME(ps.object_id) NOT LIKE 'T[0-9]%'
            AND ps.index_id > 0;

        OPEN TableCursor;

        FETCH NEXT FROM TableCursor INTO @TableName;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @SqlCmd = 
                N'UPDATE STATISTICS ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName);

            EXEC (@SqlCmd);

            FETCH NEXT FROM TableCursor INTO @TableName;
        END

        CLOSE TableCursor;
        DEALLOCATE TableCursor;
    END

    ----------------------------------------------------
    -- UPDATEUSAGE helps fix row/page count metadata
    ----------------------------------------------------
    PRINT 'Running DBCC UPDATEUSAGE...';
    DBCC UPDATEUSAGE(0);

    PRINT 'Index maintenance completed.';
END
GO
