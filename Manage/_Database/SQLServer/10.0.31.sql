truncate table dbversion;
go
insert into dbversion(dbversion) values ('10.0.31');
go

ALTER TABLE [dbo].[Analytics_InteractionLog]
ADD EventType nvarchar(100) NULL;
GO

ALTER PROCEDURE [dbo].[spLog_InsertAnalyticsInteractionLog]
	@LogGuid uniqueIdentifier,
	@ControlID nvarchar(100),
	@EventType nvarchar(100),
	@FocusTimeUTC dateTime,
	@BlurTimeUTC dateTime
AS
    SET NOCOUNT ON;
	INSERT INTO Analytics_InteractionLog ([Log_Guid], [ControlID], [EventType], [FocusTimeUTC], [BlurTimeUTC])
	VALUES (@LogGuid, @ControlID, @EventType, @FocusTimeUTC, @BlurTimeUTC)

GO

IF EXISTS(select * from [dbo].[Template_PageLog])
	INSERT INTO [Analytics_InteractionLog] (Log_Guid, ControlID, EventType, FocusTimeUtc, BlurTimeUtc)
	SELECT Log_Guid, PageTitle, 'pageOpen', DateTimeUtc, DateTimeUtc 
	FROM [Template_PageLog]
	WHERE SaveTimeUTC is null;
	GO

	INSERT INTO [Analytics_InteractionLog] (Log_Guid, ControlID, EventType, FocusTimeUtc, BlurTimeUtc)
	SELECT Log_Guid, PageTitle, 'save', SaveTimeUTC, SaveTimeUTC 
	FROM [Template_PageLog]
	WHERE SaveTimeUTC is not null;
		
GO


EXEC SP_RENAME 'dbo.Template_PageLog', 'zzTemplate_PageLog'
GO
DROP PROCEDURE [dbo].[spLog_InsertTemplatePageLog]
GO
DROP PROCEDURE [dbo].[spLog_InsertTemplateSaveLog]
GO

IF EXISTS(SELECT * FROM INFORMATION_SCHEMA.Columns WHERE TABLE_NAME = 'Intelledox_User' AND COLUMN_NAME = 'IsAnonymousUser')
exec sp_rename 'Intelledox_User.IsAnonymousUser', 'IsTemporaryUser', 'COLUMN'
GO

IF EXISTS(SELECT * FROM INFORMATION_SCHEMA.Tables WHERE TABLE_NAME = 'AnonymousUser')
exec sp_rename 'AnonymousUser', 'TemporaryUser'
GO

ALTER VIEW [dbo].[vwUserAI]
AS
	SELECT u.Business_Unit_GUID as BusinessUnitGuid,
			u.User_Guid as UserGuid,
			u.IsGuest,
			u.IsTemporaryUser,
			u.[Disabled],
			u.Username COLLATE Latin1_General_CI_AI as Username,
			ud.First_Name COLLATE Latin1_General_CI_AI as FirstName,
			ud.Last_Name COLLATE Latin1_General_CI_AI as LastName
	FROM Intelledox_User u
		LEFT JOIN Address_Book ud ON u.Address_ID = ud.Address_ID;
GO
ALTER procedure [dbo].[spUsers_updateUser]
	@UserID int,
	@Username nvarchar(256),
	@Password nvarchar(1000),
	@NewID int = 0 output,
	@WinNT_User bit,
	@BusinessUnitGUID uniqueidentifier,
	@User_GUID uniqueidentifier,
	@SelectedTheme nvarchar(100),
	@ChangePassword int,
	@PasswordSalt nvarchar(128),
	@PasswordFormat int,
	@Disabled int,
	@Address_Id int,
	@Timezone nvarchar(50),
	@Culture nvarchar(11),
	@Language nvarchar(11),
	@InvalidLogonAttempts int,
	@PasswordSetUtc datetime,
	@EulaAcceptedUtc datetime,
	@IsGuest bit,
	@TwoFactorSecret nvarchar(100),
	@IsTemporaryUser bit
as
	SET NOCOUNT ON

	DECLARE @IdTable TABLE (ID INT);

	if @UserID = 0 OR @UserID IS NULL
	begin
		INSERT INTO Intelledox_User(Username, PwdHash, WinNT_User, Business_Unit_GUID, User_Guid, SelectedTheme, 
				ChangePassword, PwdSalt, PwdFormat, [Disabled], Address_ID, Timezone, Culture, Language, IsGuest, 
				Invalid_Logon_Attempts, Password_Set_Utc, EulaAcceptanceUtc, TwoFactorSecret, IsTemporaryUser)
		OUTPUT Inserted.User_ID INTO @IdTable
		VALUES (@Username, @Password, @WinNT_User, @BusinessUnitGUID, @User_Guid, @SelectedTheme, 
				@ChangePassword, @PasswordSalt, @PasswordFormat, @Disabled, @Address_Id, @Timezone, @Culture, @Language, @IsGuest, 
				@InvalidLogonAttempts, @PasswordSetUtc, @EulaAcceptedUtc, @TwoFactorSecret, @IsTemporaryUser);
		
		SET @NewID = (SELECT ID FROM @IdTable);

		INSERT INTO User_Group_Subscription(UserGuid, GroupGuid, IsDefaultGroup)
		SELECT	@User_Guid, User_Group.Group_Guid, 0
		FROM	User_Group
		WHERE	User_Group.AutoAssignment = 1
				AND Business_Unit_Guid = @BusinessUnitGUID;
	end
	else
	begin
		IF NOT EXISTS(SELECT *
			FROM Intelledox_User
			WHERE	[User_ID] = @UserID
				AND [Disabled] = @Disabled
				AND PwdHash = @Password)
		BEGIN
			-- Clear any sessions if our user account state changes
			DELETE User_Session
			FROM User_Session
				INNER JOIN Intelledox_User ON User_Session.User_Guid = Intelledox_User.User_Guid
			WHERE Intelledox_User.[User_ID] = @UserID;
		END

		UPDATE Intelledox_User
		SET Username = @Username,  
			PwdHash = @Password, 
			WinNT_User = @WinNT_User,
			SelectedTheme = @SelectedTheme,
			ChangePassword = @ChangePassword,
			PwdSalt = @PasswordSalt,
			PwdFormat = @PasswordFormat,
			[Disabled] = @Disabled,
			Timezone = @Timezone,
			Culture = @Culture,
			Language = @Language,
			Address_ID = @Address_Id,
			Invalid_Logon_Attempts = @InvalidLogonAttempts,
			Password_Set_Utc = @PasswordSetUtc,
			EulaAcceptanceUtc = @EulaAcceptedUtc,
			TwoFactorSecret = @TwoFactorSecret,
			IsTemporaryUser = @IsTemporaryUser
		WHERE [User_ID] = @UserID;
	end
GO

ALTER PROCEDURE [dbo].[spUsers_UserCount]
	@BusinessUnitGuid uniqueidentifier
AS
BEGIN
	SELECT SUM(CASE WHEN IsGuest = 0 AND Disabled = 0 AND IsTemporaryUser = 0 THEN 1 ELSE 0 END) 
	FROM Intelledox_User
	WHERE Business_Unit_GUID = @BusinessUnitGuid;
END
GO

ALTER PROCEDURE [dbo].[spUsers_UserGroupByUserCount]
	@BusinessUnitGUID uniqueidentifier,
	@Username nvarchar(50) = '',
	@UserGroupID int = 0,
	@ShowActive int = 0,
	@Firstname nvarchar(50) = '',
	@Lastname nvarchar(50) = ''
AS
BEGIN
	if @UserGroupID = 0	--all user groups
	begin
		if @Username = '' AND @Firstname = '' AND @Lastname = '' AND @ShowActive = 0
		begin
			select	COUNT(*)
			from	Intelledox_User a
			where	a.Business_Unit_GUID = @BusinessUnitGUID AND a.IsTemporaryUser = 0
		end
		else
		begin
			select	COUNT(*)
			from	Intelledox_User a
				left join Address_Book d on a.Address_ID = d.Address_ID
			where	(@Username = '' OR a.[Username] COLLATE Latin1_General_CI_AI like (@Username + '%') COLLATE Latin1_General_CI_AI)
				AND (@Firstname = '' OR d.[First_Name] COLLATE Latin1_General_CI_AI like ('%' + @Firstname + '%') COLLATE Latin1_General_CI_AI)
				AND (@Lastname = '' or d.[Last_Name] COLLATE Latin1_General_CI_AI like ('%' + @Lastname + '%') COLLATE Latin1_General_CI_AI)
				AND (a.Business_Unit_GUID = @BusinessUnitGUID)
				AND ((@ShowActive = 0 AND a.IsTemporaryUser = 0)
					OR (@ShowActive = 1 AND a.[Disabled] = 0 AND a.IsTemporaryUser = 0)
					OR (@ShowActive = 2 AND a.[Disabled] = 1 AND a.IsTemporaryUser = 0)
					OR (@ShowActive = 3 AND a.IsTemporaryUser = 1))
		end
	end
	else
	begin
		if @UserGroupID = -1	--users with no user groups
		begin
			select	COUNT(*)
			from	Intelledox_User a
				left join Address_Book d on a.Address_Id = d.Address_id
			where	(@Username = '' OR a.[Username] COLLATE Latin1_General_CI_AI like (@Username + '%') COLLATE Latin1_General_CI_AI)
				AND (@Firstname = '' OR d.[First_Name] COLLATE Latin1_General_CI_AI like ('%' + @Firstname + '%') COLLATE Latin1_General_CI_AI)
				AND (@Lastname = '' or d.[Last_Name] COLLATE Latin1_General_CI_AI like ('%' + @Lastname + '%') COLLATE Latin1_General_CI_AI)
				AND	a.User_Guid not in (
						select a.userGuid
						from user_group_subscription a 
						inner join user_Group b on a.GroupGuid = b.Group_Guid
					)
				AND (a.Business_Unit_GUID = @BusinessUnitGUID)
				AND ((@ShowActive = 0 AND a.IsTemporaryUser = 0)
					OR (@ShowActive = 1 AND a.[Disabled] = 0 AND a.IsTemporaryUser = 0)
					OR (@ShowActive = 2 AND a.[Disabled] = 1 AND a.IsTemporaryUser = 0)
					OR (@ShowActive = 3 AND a.IsTemporaryUser = 1))
		end
		else			--users in specified user group
		begin
			select	COUNT(*)
			from	Intelledox_User a
				inner join User_Group_Subscription c on a.User_Guid = c.UserGuid
				left join Address_Book d on a.Address_Id = d.Address_id
			where	(@Username = '' OR a.[Username] COLLATE Latin1_General_CI_AI like (@Username + '%') COLLATE Latin1_General_CI_AI)
				AND (@Firstname = '' OR d.[First_Name] COLLATE Latin1_General_CI_AI like ('%' + @Firstname + '%') COLLATE Latin1_General_CI_AI)
				AND (@Lastname = '' or d.[Last_Name] COLLATE Latin1_General_CI_AI like ('%' + @Lastname + '%') COLLATE Latin1_General_CI_AI)
				AND	c.GroupGuid = (SELECT Group_Guid FROM User_Group WHERE User_Group_id = @UserGroupID)
				AND (a.Business_Unit_GUID = @BusinessUnitGUID)
				AND ((@ShowActive = 0 AND a.IsTemporaryUser = 0)
					OR (@ShowActive = 1 AND a.[Disabled] = 0 AND a.IsTemporaryUser = 0)
					OR (@ShowActive = 2 AND a.[Disabled] = 1 AND a.IsTemporaryUser = 0)
					OR (@ShowActive = 3 AND a.IsTemporaryUser = 1))
		end
	end
END

GO
ALTER PROCEDURE [dbo].[spUsers_UsersPaging]
	@BusinessUnitGUID uniqueidentifier,
	@Username nvarchar(50) = '',
	@UserGroupID int = 0,
	@ShowActive int = 0,
	@Firstname nvarchar(50) = '',
	@Lastname nvarchar(50) = '',
	@StartRow int,
	@MaximumRows int
AS
BEGIN
	if @UserGroupID = 0	--all user groups
	begin
		if @Username = '' AND @Firstname = '' AND @Lastname = '' AND @ShowActive = 0 
		begin
			select *
			from (
				select	a.*, d.[First_Name], d.[Last_Name], d.[Email_Address], d.[Full_Name], ROW_NUMBER() OVER (ORDER BY a.[Username]) AS RowRank
				from	Intelledox_User a
					left join Address_Book d on a.Address_ID = d.Address_ID
				where	a.Business_Unit_GUID = @BusinessUnitGUID AND a.IsTemporaryUser = 0
				) as RankedUsers
			WHERE RowRank > @StartRow AND RowRank <= (@StartRow + @MaximumRows)
		end
		else
		begin
			select *
			from (
				select	a.*, d.[First_Name], d.[Last_Name], d.[Email_Address], d.[Full_Name], ROW_NUMBER() OVER (ORDER BY a.[Username]) AS RowRank
				from	Intelledox_User a
					left join Address_Book d on a.Address_ID = d.Address_ID
				where	(@Username = '' OR a.[Username] COLLATE Latin1_General_CI_AI like (@Username + '%') COLLATE Latin1_General_CI_AI)
					AND (@Firstname = '' OR d.[First_Name] COLLATE Latin1_General_CI_AI like ('%' + @Firstname + '%') COLLATE Latin1_General_CI_AI)
					AND (@Lastname = '' or d.[Last_Name] COLLATE Latin1_General_CI_AI like ('%' + @Lastname + '%') COLLATE Latin1_General_CI_AI)
					AND (a.Business_Unit_GUID = @BusinessUnitGUID)
					AND ((@ShowActive = 0 AND a.IsTemporaryUser = 0)
						OR (@ShowActive = 1 AND a.[Disabled] = 0 AND a.IsTemporaryUser = 0)
						OR (@ShowActive = 2 AND a.[Disabled] = 1 AND a.IsTemporaryUser = 0)
						OR (@ShowActive = 3 AND a.IsTemporaryUser = 1))
				) as RankedUsers
			WHERE RowRank > @StartRow AND RowRank <= (@StartRow + @MaximumRows)
		end
	end
	else
	begin
		if @UserGroupID = -1	--users with no user groups
		begin
			select *
			from (
				select	a.*,  d.[First_Name], d.[Last_Name], d.[Email_Address], d.[Full_Name], ROW_NUMBER() OVER (ORDER BY a.[Username]) AS RowRank
				from	Intelledox_User a
					left join Address_Book d on a.Address_Id = d.Address_id
				where	(@Username = '' OR a.[Username] COLLATE Latin1_General_CI_AI like (@Username + '%') COLLATE Latin1_General_CI_AI)
					AND (@Firstname = '' OR d.[First_Name] COLLATE Latin1_General_CI_AI like ('%' + @Firstname + '%') COLLATE Latin1_General_CI_AI)
					AND (@Lastname = '' or d.[Last_Name] COLLATE Latin1_General_CI_AI like ('%' + @Lastname + '%') COLLATE Latin1_General_CI_AI)
					AND	a.User_Guid not in (
							select a.userGuid
							from user_group_subscription a 
							inner join user_Group b on a.GroupGuid = b.Group_Guid
						)
					AND (a.Business_Unit_GUID = @BusinessUnitGUID)
					AND ((@ShowActive = 0 AND a.IsTemporaryUser = 0)
						OR (@ShowActive = 1 AND a.[Disabled] = 0 AND a.IsTemporaryUser = 0)
						OR (@ShowActive = 2 AND a.[Disabled] = 1 AND a.IsTemporaryUser = 0)
						OR (@ShowActive = 3 AND a.IsTemporaryUser = 1))
				) as RankedUsers
			WHERE RowRank > @StartRow AND RowRank <= (@StartRow + @MaximumRows)
		end
		else			--users in specified user group
		begin
			select *
			from (
				select	a.*,  d.[First_Name], d.[Last_Name], d.[Email_Address], d.[Full_Name], ROW_NUMBER() OVER (ORDER BY a.[Username]) AS RowRank
				from	Intelledox_User a
					inner join User_Group_Subscription c on a.User_Guid = c.UserGuid
					left join Address_Book d on a.Address_Id = d.Address_id
				where	(@Username = '' OR a.[Username] COLLATE Latin1_General_CI_AI like (@Username + '%') COLLATE Latin1_General_CI_AI)
					AND (@Firstname = '' OR d.[First_Name] COLLATE Latin1_General_CI_AI like ('%' + @Firstname + '%') COLLATE Latin1_General_CI_AI)
					AND (@Lastname = '' or d.[Last_Name] COLLATE Latin1_General_CI_AI like ('%' + @Lastname + '%') COLLATE Latin1_General_CI_AI)
					AND	c.GroupGuid = (SELECT Group_Guid FROM User_Group WHERE User_Group_id = @UserGroupID)
					AND (a.Business_Unit_GUID = @BusinessUnitGUID)
					AND ((@ShowActive = 0 AND a.IsTemporaryUser = 0)
						OR (@ShowActive = 1 AND a.[Disabled] = 0 AND a.IsTemporaryUser = 0)
						OR (@ShowActive = 2 AND a.[Disabled] = 1 AND a.IsTemporaryUser = 0)
						OR (@ShowActive = 3 AND a.IsTemporaryUser = 1))
				) as RankedUsers
			WHERE RowRank > @StartRow AND RowRank <= (@StartRow + @MaximumRows)
		end
	end
END
GO

ALTER PROCEDURE [dbo].[spUser_InsertIntoAccessCode]
	@UserGuid uniqueidentifier,
	@AccessCode nvarchar(50)
AS
BEGIN
	IF (SELECT COUNT(UserGuid) FROM TemporaryUser WHERE UserGuid = @UserGuid) > 0
	BEGIN
		UPDATE TemporaryUser
		SET AccessCode = @AccessCode
		WHERE UserGuid = @UserGuid
	END
	ELSE
	BEGIN
		INSERT INTO TemporaryUser (UserGuid, AccessCode)
		VALUES (@UserGuid, @AccessCode) 
	END
END
GO

ALTER PROCEDURE [dbo].[spUser_GetUserFromAccessCode]
	@AccessCode nvarchar(50)
AS
BEGIN
	IF @AccessCode != ''
	BEGIN
	SELECT Intelledox_User.*, Address_Book.Email_Address FROM Intelledox_User
	INNER JOIN TemporaryUser on TemporaryUser.UserGuid = Intelledox_User.User_Guid
	INNER JOIN Address_Book on Intelledox_User.Address_Id = Address_Book.Address_id
	WHERE TemporaryUser.AccessCode = @AccessCode AND Intelledox_User.IsTemporaryUser = 1
	END
END
GO

ALTER procedure [dbo].[spUsers_RemoveUser]
	@UserGuid uniqueidentifier
AS
	SET NOCOUNT ON;

	DECLARE @UserId int;
	DECLARE @AddressId int;
	
	SELECT	@UserId = [User_Id], @AddressId = Address_ID
	FROM	Intelledox_User
	WHERE	User_Guid = @UserGuid;

	-- In case a restored user has been re-deleted, clear the history item
	DELETE Intelledox_UserDeleted WHERE UserGuid = @UserGuid;

	INSERT INTO Intelledox_UserDeleted(UserGuid, Username, BusinessUnitGuid, FirstName, LastName, Email, User_ID)
	SELECT Intelledox_User.User_Guid, Intelledox_User.Username, Intelledox_User.Business_Unit_GUID,
			Address_Book.First_Name, Address_Book.Last_Name, Address_Book.Email_Address, @UserId
	FROM Intelledox_User
		LEFT JOIN Address_Book ON Intelledox_User.Address_ID = Address_Book.Address_ID
	WHERE Intelledox_User.User_Guid = @UserGuid;
	
	DELETE Address_Book WHERE Address_ID = @AddressId;
	DELETE User_Address_Book WHERE [User_Id] = @UserId;
	DELETE User_Group_Subscription WHERE UserGuid = @UserGuid;
	DELETE User_Session WHERE User_Guid = @UserGuid;
	UPDATE Template SET LockedByUserGuid = null WHERE LockedByUserGuid = @UserGuid;
	DELETE Intelledox_User WHERE User_Guid = @UserGuid;
	DELETE TemporaryUser WHERE UserGuid = @UserGuid;

GO



ALTER procedure [dbo].[spCleanup]
	@HasAnyTransactionalLicense bit
AS
    SET NOCOUNT ON
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @DocumentCleanupDate DateTime;
	DECLARE @DocumentBinaryCleanupDate DateTime;
	DECLARE @SeparateDateForBinaries bit;
	DECLARE @DownloadableDocNum int;
	DECLARE @GenerationCleanupDate DateTime;
	DECLARE @AuditCleanupDate DateTime;
	DECLARE @WorkflowCleanupDate DateTime;
	DECLARE @LogoutCleanupDate DateTime;
	DECLARE @TransactionLogCleanupDate DateTime;
	DECLARE @TemporaryUsersCleanup DateTime;

    SET @DocumentCleanupDate = DATEADD(hour, -CAST((SELECT OptionValue 
                                        FROM Global_Options 
                                        WHERE OptionCode = 'CLEANUP_HOURS') AS float), GetUtcDate());

	SET @DownloadableDocNum = (SELECT OptionValue 
								FROM Global_Options 
								WHERE OptionCode = 'DOWNLOADABLE_DOC_NUM');

    SET @GenerationCleanupDate = DATEADD(day, -CAST((SELECT OptionValue 
                                        FROM Global_Options 
                                        WHERE OptionCode = 'GENERATION_RETENTION') AS float), GetUtcDate());

    SET @AuditCleanupDate = DATEADD(day, -CAST((SELECT OptionValue 
                                        FROM Global_Options 
                                        WHERE OptionCode = 'AUDIT_RETENTION') AS float), GetUtcDate());

    SET @WorkflowCleanupDate = DATEADD(day, -CAST((SELECT OptionValue 
                                        FROM Global_Options 
                                        WHERE OptionCode = 'WORKFLOW_RETENTION') AS float), GetUtcDate());
												
    SET @LogoutCleanupDate = DATEADD(day, -1, GetUtcDate());
											
    SET @TransactionLogCleanupDate = DATEADD(year, -2, GetUtcDate());

	SET @TemporaryUsersCleanup = DATEADD(HOUR, -2, GetUtcDate());
										
    DECLARE @GuidId uniqueidentifier;
    CREATE TABLE #ExpiredItems 
    ( 
        Id uniqueidentifier NOT NULL PRIMARY KEY
    )
	
	IF (@HasAnyTransactionalLicense = 1 AND (SELECT OptionValue 
                                        FROM Global_Options 
                                        WHERE OptionCode = 'CLEANUP_HOURS') < (90 * 24))
										
	BEGIN
		SET @DocumentBinaryCleanupDate = @DocumentCleanupDate;
		SET @DocumentCleanupDate = DATEADD(hour, -(90 * 24), GetUtcDate());
		SET @SeparateDateForBinaries = 1;
	END
	ELSE
	BEGIN
		SET @SeparateDateForBinaries = 0;
	END


	-- ==================================================
	-- Expired documents
	IF (@DownloadableDocNum = 0)
	BEGIN
		INSERT #ExpiredItems (Id)
		SELECT DISTINCT JobId
		FROM Document WITH (READUNCOMMITTED)
		WHERE DateCreated < @DocumentCleanupDate;
	END
	ELSE
	BEGIN
		-- Get the last N jobs grouped by user
		WITH GroupedDocuments AS (
			SELECT JobId, ROW_NUMBER()
			OVER (PARTITION BY UserGuid ORDER BY DateCreated DESC) AS RN
			FROM (
				SELECT	JobId, UserGuid, DateCreated
				FROM	Document WITH (READUNCOMMITTED)
				GROUP BY JobId, UserGuid, DateCreated
				) ds
			)
		INSERT #ExpiredItems (Id)
		SELECT DISTINCT JobId
		FROM Document WITH (READUNCOMMITTED)
		WHERE DateCreated < @DocumentCleanupDate
			AND JobId NOT IN (
				SELECT	JobId
				FROM	GroupedDocuments WITH (READUNCOMMITTED)
				WHERE	RN <= @DownloadableDocNum
			);
	END

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ExpiredItemCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT Id FROM #ExpiredItems 
		
        OPEN ExpiredItemCursor;
        FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
				DELETE FROM Document WHERE JobId = @GuidId;
                FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;
            END

        CLOSE ExpiredItemCursor;
        DEALLOCATE ExpiredItemCursor;
    END
	
	-- ==================================================
	-- Remove binaries from Document table, if required
	IF (@SeparateDateForBinaries = 1)
	BEGIN	
		IF (@DownloadableDocNum = 0)
		BEGIN
			INSERT #ExpiredItems (Id)
			SELECT DISTINCT JobId
			FROM Document WITH (READUNCOMMITTED)
			WHERE DateCreated < @DocumentBinaryCleanupDate;
		END
		ELSE
		BEGIN
			-- Get the last N jobs grouped by user
			WITH GroupedDocuments AS (
				SELECT JobId, ROW_NUMBER()
				OVER (PARTITION BY UserGuid ORDER BY DateCreated DESC) AS RN
				FROM (
					SELECT	JobId, UserGuid, DateCreated
					FROM	Document WITH (READUNCOMMITTED)
					GROUP BY JobId, UserGuid, DateCreated
					) ds
				)
			INSERT #ExpiredItems (Id)
			SELECT DISTINCT JobId
			FROM Document WITH (READUNCOMMITTED)
			WHERE DateCreated < @DocumentBinaryCleanupDate
				AND JobId NOT IN (
					SELECT	JobId
					FROM	GroupedDocuments WITH (READUNCOMMITTED)
					WHERE	RN <= @DownloadableDocNum
				);
		END

		IF @@ROWCOUNT <> 0 
		BEGIN 
			DECLARE ExpiredItemCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
			FOR SELECT Id FROM #ExpiredItems 
		
			OPEN ExpiredItemCursor;
			FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;

			WHILE @@FETCH_STATUS = 0 
				BEGIN
			
					UPDATE Document 
					SET DocumentBinary = 0x,
						DocumentLength = -1
					WHERE JobId = @GuidId;

					FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;
				END

			CLOSE ExpiredItemCursor;
			DEALLOCATE ExpiredItemCursor;
		END
	END

	-- ==================================================
	-- Expired generation logs
	TRUNCATE TABLE #ExpiredItems;

	INSERT #ExpiredItems (Id)
	SELECT Log_Guid
	FROM Template_Log WITH (READUNCOMMITTED)
	WHERE DateTime_Start < @GenerationCleanupDate
		AND CompletionState <> 0;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ExpiredItemCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT Id FROM #ExpiredItems 

        OPEN ExpiredItemCursor;
        FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM Template_Log WHERE Log_Guid = @GuidId;
                FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;
            END

        CLOSE ExpiredItemCursor;
        DEALLOCATE ExpiredItemCursor;
    END 

	-- ==================================================
	-- Expired Data Focus Transition Logs
	TRUNCATE TABLE #ExpiredItems;

	INSERT #ExpiredItems (Id)
	SELECT DISTINCT(Log_Guid)
	FROM Analytics_InteractionLog WITH (READUNCOMMITTED)
	WHERE FocusTimeUTC < @GenerationCleanupDate

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ExpiredItemCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT Id FROM #ExpiredItems 

        OPEN ExpiredItemCursor;
        FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM Analytics_InteractionLog WHERE Log_Guid = @GuidId;
                FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;
            END

        CLOSE ExpiredItemCursor;
        DEALLOCATE ExpiredItemCursor;
    END

	-- ==================================================
	-- Expired process job logs
	TRUNCATE TABLE #ExpiredItems;

	INSERT #ExpiredItems (Id)
	SELECT JobId
	FROM ProcessJob WITH (READUNCOMMITTED)
	WHERE DateStarted < @GenerationCleanupDate
		AND CurrentStatus >= 4;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ExpiredItemCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT Id FROM #ExpiredItems 

        OPEN ExpiredItemCursor;
        FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM ProcessJob WHERE JobId = @GuidId;
                FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;
            END

        CLOSE ExpiredItemCursor;
        DEALLOCATE ExpiredItemCursor;
    END 


	-- ==================================================
	-- Expired sessions
	TRUNCATE TABLE #ExpiredItems;

	INSERT #ExpiredItems (Id)
	SELECT Session_Guid
	FROM User_Session WITH (READUNCOMMITTED)
	WHERE Modified_Date < DateAdd(year, -1, GetUtcDate());

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ExpiredItemCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT Id FROM #ExpiredItems 

        OPEN ExpiredItemCursor;
        FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM User_Session WHERE Session_Guid = @GuidId;
                FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;
            END

        CLOSE ExpiredItemCursor;
        DEALLOCATE ExpiredItemCursor;
    END 


	-- ==================================================
	-- Expired workflow history
	TRUNCATE TABLE #ExpiredItems;

	INSERT #ExpiredItems (Id)
	SELECT ActionListId
	FROM ActionList WITH (READUNCOMMITTED)
	WHERE DateCreatedUtc < @WorkflowCleanupDate;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ExpiredItemCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT Id FROM #ExpiredItems 

        OPEN ExpiredItemCursor;
        FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
				BEGIN TRANSACTION AL;

                DELETE FROM ActionListState 
				WHERE ActionListId = @GuidId
					AND ActionListId NOT IN (
						SELECT	ActionListId
						FROM	ActionListState
						WHERE	ActionListId = @GuidId
								AND IsComplete = 0
					);

				DELETE FROM ActionList 
				WHERE ActionListId = @GuidId
					AND ActionListId NOT IN (
						SELECT	ActionListId
						FROM	ActionListState
						WHERE	ActionListId = @GuidId
								AND IsComplete = 0
					);

				COMMIT TRANSACTION AL;

                FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;
            END

        CLOSE ExpiredItemCursor;
        DEALLOCATE ExpiredItemCursor;
    END 

	-- ==================================================
	-- Expired TemporaryUsers
	TRUNCATE TABLE #ExpiredItems;

  	INSERT #ExpiredItems (Id)
	SELECT DISTINCT(UserGuid)
	FROM TemporaryUser WITH (READUNCOMMITTED)
	INNER JOIN Intelledox_User ON TemporaryUser.UserGuid = Intelledox_User.User_Guid
	INNER JOIN Template_Log ON Intelledox_User.User_ID = Template_Log.User_ID
	WHERE Intelledox_User.IsTemporaryUser = 1 AND 
		Template_Log.ActionListStateId = '00000000-0000-0000-0000-000000000000' AND
		Template_Log.DateTime_Finish < @TemporaryUsersCleanup;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ExpiredItemCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT Id FROM #ExpiredItems 

        OPEN ExpiredItemCursor;
        FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                EXEC spUsers_RemoveUser @GuidId;
                FETCH NEXT FROM ExpiredItemCursor INTO @GuidId;
            END

        CLOSE ExpiredItemCursor;
        DEALLOCATE ExpiredItemCursor;
    END
	
    DROP TABLE #ExpiredItems;


	-- ==================================================
	-- Expired audit logs
	DECLARE @BigId bigint;
    CREATE TABLE #ExpiredAudit
    ( 
        Id bigint NOT NULL PRIMARY KEY
    )

	INSERT #ExpiredAudit (Id)
	SELECT ID
	FROM AuditLog WITH (READUNCOMMITTED)
	WHERE DateCreatedUtc < @AuditCleanupDate;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ExpiredAuditCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT Id FROM #ExpiredAudit 

        OPEN ExpiredAuditCursor;
        FETCH NEXT FROM ExpiredAuditCursor INTO @BigId;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM AuditLog WHERE ID = @BigId;
                FETCH NEXT FROM ExpiredAuditCursor INTO @BigId;
            END

        CLOSE ExpiredAuditCursor;
        DEALLOCATE ExpiredAuditCursor;
    END 
	
    DROP TABLE #ExpiredAudit;
	

	-- ==================================================
	-- Expired event logs
	DECLARE @IntId int;
    CREATE TABLE #ExpiredEvent
    ( 
        Id int NOT NULL PRIMARY KEY
    )

	INSERT #ExpiredEvent (Id)
	SELECT LogEventID
	FROM EventLog WITH (READUNCOMMITTED)
	WHERE [DateTime] < @AuditCleanupDate;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ExpiredEventCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT Id FROM #ExpiredEvent 

        OPEN ExpiredEventCursor;
        FETCH NEXT FROM ExpiredEventCursor INTO @IntId;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM EventLog WHERE LogEventID = @IntId;
                FETCH NEXT FROM ExpiredEventCursor INTO @IntId;
            END

        CLOSE ExpiredEventCursor;
        DEALLOCATE ExpiredEventCursor;
    END 
	
    DROP TABLE #ExpiredEvent;

	-- ==================================================
	-- Expired logouts
	DECLARE @CookieValue varchar(200);
    CREATE TABLE #ExpiredLogout
    ( 
        AuthCookieValue varchar(200) NOT NULL PRIMARY KEY
    )

	INSERT #ExpiredLogout (AuthCookieValue)
	SELECT DISTINCT AuthCookieValue
	FROM LoggedOutSessions WITH (READUNCOMMITTED)
	WHERE [TimeLoggedOut] < @LogoutCleanupDate;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE LogoutEventCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT AuthCookieValue FROM #ExpiredLogout 

        OPEN LogoutEventCursor;
        FETCH NEXT FROM LogoutEventCursor INTO @CookieValue;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM LoggedOutSessions WHERE AuthCookieValue = @CookieValue;
                FETCH NEXT FROM LogoutEventCursor INTO @CookieValue;
            END

        CLOSE LogoutEventCursor;
        DEALLOCATE LogoutEventCursor;
    END 
	
    DROP TABLE #ExpiredLogout;
	
	-- ==================================================
	-- Expired transaction logs
	-- Actions
	DECLARE @Date datetime;
    CREATE TABLE #ExpiredActionLog
    ( 
        DateTimeUTC datetime NOT NULL PRIMARY KEY
    )

	INSERT #ExpiredActionLog (DateTimeUTC)
	SELECT DISTINCT DateTimeUTC
	FROM Action_Log WITH (READUNCOMMITTED)
	WHERE [DateTimeUTC] < @TransactionLogCleanupDate;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE ActionLogCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT DateTimeUTC FROM #ExpiredActionLog 

        OPEN ActionLogCursor;
        FETCH NEXT FROM ActionLogCursor INTO @Date;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM Action_Log WHERE DateTimeUTC = @Date;
                FETCH NEXT FROM ActionLogCursor INTO @Date;
            END

        CLOSE ActionLogCursor;
        DEALLOCATE ActionLogCursor;
    END 
	
    DROP TABLE #ExpiredActionLog;

	-- Escalations
    CREATE TABLE #ExpiredEscalationLog
    ( 
        DateTimeUTC datetime NOT NULL PRIMARY KEY
    )

	INSERT #ExpiredEscalationLog (DateTimeUTC)
	SELECT DISTINCT DateTimeUTC
	FROM Escalation_Log WITH (READUNCOMMITTED)
	WHERE [DateTimeUTC] < @TransactionLogCleanupDate;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE EscalationLogCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT DateTimeUTC FROM #ExpiredEscalationLog 

        OPEN EscalationLogCursor;
        FETCH NEXT FROM EscalationLogCursor INTO @Date;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM Escalation_Log WHERE DateTimeUTC = @Date;
                FETCH NEXT FROM EscalationLogCursor INTO @Date;
            END

        CLOSE EscalationLogCursor;
        DEALLOCATE EscalationLogCursor;
    END 
	
    DROP TABLE #ExpiredEscalationLog;
	
	-- Emails
    CREATE TABLE #ExpiredEmailLog
    ( 
        DateTimeUTC datetime NOT NULL PRIMARY KEY
    )

	INSERT #ExpiredEmailLog (DateTimeUTC)
	SELECT DISTINCT DateTimeUTC
	FROM Email_Log WITH (READUNCOMMITTED)
	WHERE [DateTimeUTC] < @TransactionLogCleanupDate;

    IF @@ROWCOUNT <> 0 
    BEGIN 
        DECLARE EmailLogCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR SELECT DateTimeUTC FROM #ExpiredEmailLog 

        OPEN EmailLogCursor;
        FETCH NEXT FROM EmailLogCursor INTO @Date;

        WHILE @@FETCH_STATUS = 0 
            BEGIN
                DELETE FROM Email_Log WHERE DateTimeUTC = @Date;
                FETCH NEXT FROM EmailLogCursor INTO @Date;
            END

        CLOSE EmailLogCursor;
        DEALLOCATE EmailLogCursor;
    END 
	
    DROP TABLE #ExpiredEmailLog;
	
GO

DROP PROCEDURE [spLog_UpdateBookmarkGroupLog]
GO

ALTER PROCEDURE [dbo].[spLog_UpdateTemplateLog]
	@LogGuid uniqueidentifier,
	@LastGroupGuid uniqueidentifier,
	@AnswerFile xml,
	@EncryptedAnswerFile varbinary(MAX),
	@ActionListStateId uniqueidentifier = '00000000-0000-0000-0000-000000000000',
	@Latitude decimal(9,6) = NULL,
	@Longitude decimal(9,6) = NULL
AS
	UPDATE	Template_Log WITH (ROWLOCK, UPDLOCK)
	SET		Answer_File = @AnswerFile,
			Last_Bookmark_Group_Guid = @LastGroupGuid,
			ActionListStateId = @ActionListStateId,
			EncryptedAnswerFile = @EncryptedAnswerFile,
			Latitude = ISNULL(@Latitude, Latitude),
			Longitude = ISNULL(@Longitude, Longitude)
	WHERE	Log_Guid = @LogGuid;

GO

ALTER procedure [dbo].[spLog_CompleteProjectLog]
	@LogGuid uniqueidentifier,
	@FinishDate datetime,
	@MessageXml xml = null,
	@UpdateRecent bit = 0,
	@IsWorkflowState bit = 0,
	@RunId uniqueidentifier = null,
	@Latitude decimal(9,6) = NULL,
	@Longitude decimal(9,6) = NULL
AS
	DECLARE @UserGuid uniqueidentifier;
	DECLARE @TemplateGroupGuid uniqueidentifier;
	
	SET NOCOUNT ON;

	UPDATE	Template_Log 
	SET		DateTime_Finish = @FinishDate, 
			Completionstate = CASE WHEN @IsWorkflowState = 1 THEN 2 ELSE 3 END,
			Messages = @MessageXml,
			RunId = ISNULL(@RunId, RunId),
			Latitude = ISNULL(@Latitude, Latitude),
			Longitude = ISNULL(@Longitude, Longitude)
	WHERE	Log_Guid = @LogGuid;
	
	
	If @UpdateRecent = 1
	BEGIN
		SET @UserGuid = (SELECT User_Guid 
							FROM Template_Log
							INNER JOIN Intelledox_User ON Template_Log.[User_ID] = Intelledox_User.[User_ID]
							WHERE Log_Guid = @LogGuid);

		SET	@TemplateGroupGuid = (SELECT Template_Group_Guid 
								FROM Template_Log
								INNER JOIN Template_Group ON Template_Log.Template_Group_ID = Template_Group.Template_Group_ID
								WHERE Log_Guid = @LogGuid);

		--update recent completed log
		UPDATE	Template_Recent
		SET		Log_Guid = @LogGuid
		WHERE	User_Guid = @UserGuid 
				AND Template_Group_Guid = @TemplateGroupGuid;
	END

GO

ALTER VIEW [dbo].[vwUserAvailableForms]
AS

SELECT f.Folder_Name AS FolderName, 
f.Business_Unit_Guid, u.User_Guid AS UserGuid, 
   tg.HelpText as ProjectHelpText, t.[Name] as ProjectName,   
   tg.Template_Group_Guid AS ProjectGroupGuid, 
        CASE WHEN t.Template_Type_ID = 1 THEN 'Form'
             WHEN t.Template_Type_ID = 2 THEN 'Layout'
             WHEN t.Template_Type_ID = 4 THEN 'FragmentPage'
             WHEN t.Template_Type_ID = 5 THEN 'FragmentPortion'
             WHEN t.Template_Type_ID = 6 THEN 'Dashboard'
             ELSE CAST(t.Template_Type_ID AS varchar)
        END AS ProjectType, tg.FeatureFlags, 
   CASE WHEN Log_Guid IS NULL THEN cast(cast(0 as binary) as uniqueidentifier) ELSE l.Log_Guid END AS LogGuid, l.DateTime_Start AS DateTimeStart 
 FROM Folder f  
 LEFT JOIN ( SELECT DISTINCT Folder_Group.FolderGuid, Intelledox_User.User_Guid FROM Folder_Group  
      INNER JOIN User_Group ON Folder_Group.GroupGuid = User_Group.Group_Guid  
      INNER JOIN User_Group_Subscription ON User_Group.Group_Guid = User_Group_Subscription.GroupGuid  
      INNER JOIN Intelledox_User ON User_Group_Subscription.UserGuid = Intelledox_User.User_Guid  ) u
	   ON u.FolderGuid = f.Folder_Guid
   INNER JOIN Template_Group tg on f.folder_Guid = tg.Folder_Guid  
   INNER JOIN Template t on tg.Template_Guid =t.Template_Guid  
   LEFT JOIN Template_Recent l on tg.Template_Group_Guid = l.Template_Group_Guid  AND l.User_Guid = u.User_Guid
 WHERE (tg.EnforcePublishPeriod = 0   
    OR ((tg.PublishStartDate IS NULL OR tg.PublishStartDate < getdate())  
    AND (tg.PublishFinishDate IS NULL OR tg.PublishFinishDate > getdate())))

GO

ALTER VIEW [vwProjectDetails]
AS
SELECT  t.Template_ID, t.Name, t.Template_Type_ID, t.Template_Guid, t.Template_Version, t.HelpText, 
        t.Business_Unit_GUID, t.Modified_Date, t.Modified_By, t.Comment, t.LockedByUserGuid, t.FeatureFlags, 
        t.IsMajorVersion, tg.Template_Group_ID, tg.Template_Group_Guid, tg.HelpText AS GroupHelpText, tg.AllowPreview, tg.PostGenerateText, 
        tg.UpdateDocumentFields, tg.EnforceValidation, tg.WizardFinishText, tg.EnforcePublishPeriod, tg.PublishStartDate, tg.PublishFinishDate, 
        tg.HideNavigationPane, tg.Layout_Guid, tg.Layout_Version, tg.Folder_Guid, 
        CASE WHEN t.Template_Type_ID = 1 THEN 'Form'
             WHEN t.Template_Type_ID = 2 THEN 'Layout'
             WHEN t.Template_Type_ID = 4 THEN 'FragmentPage'
             WHEN t.Template_Type_ID = 5 THEN 'FragmentPortion'
             WHEN t.Template_Type_ID = 6 THEN 'Dashboard'
             ELSE t.Template_Type_ID
        END AS Project_Type
FROM    dbo.Template AS t INNER JOIN
        dbo.Template_Group AS tg ON tg.Template_Guid = t.Template_Guid

GO
