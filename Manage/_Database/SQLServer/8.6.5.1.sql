truncate table dbversion;
go
insert into dbversion(dbversion) values ('8.6.5.1');
go

CREATE PROCEDURE [dbo].[spSync_ProjectGroup]
	@ProjectGroupId int,
	@ProjectGroupGuid uniqueidentifier,
	@HelpText nvarchar(4000),
	@AllowPreview bit,
	@WizardFinishText nvarchar(max),
	@PostGenerateText nvarchar(4000),
	@UpdateDocumentFields bit,
	@EnforceValidation bit,
	@HideNavigationPane bit,
	@EnforcePublishPeriod bit,
	@PublishStartDate datetime,
	@PublishFinishDate datetime,
	@ProjectGuid uniqueidentifier,
	@LayoutGuid uniqueidentifier,
	@ProjectVersion nvarchar(10),
	@LayoutVersion nvarchar(10),
	@FolderGuid uniqueidentifier,
	@ShowFormActivity bit,
	@MatchProjectVersion bit
AS
	IF NOT EXISTS(SELECT * FROM Template_Group WHERE template_group_guid = @ProjectGroupGuid)
	BEGIN
		SET IDENTITY_INSERT Template_Group ON
		INSERT INTO Template_Group (Template_Group_ID, Template_Group_Guid, HelpText, AllowPreview, PostGenerateText, 
				UpdateDocumentFields, EnforceValidation, WizardFinishText, EnforcePublishPeriod,
				PublishStartDate, PublishFinishDate, HideNavigationPane, Template_Guid, Layout_Guid,
				Template_Version, Layout_Version, Folder_Guid, ShowFormActivity, MatchProjectVersion)
		VALUES (@ProjectGroupId, @ProjectGroupGuid, @HelpText, @AllowPreview, @PostGenerateText, 
				@UpdateDocumentFields, @EnforceValidation, @WizardFinishText, @EnforcePublishPeriod,
				@PublishStartDate, @PublishFinishDate, @HideNavigationPane, @ProjectGuid, @LayoutGuid,
				@ProjectVersion, @LayoutVersion, @FolderGuid, @ShowFormActivity, @MatchProjectVersion);
		SET IDENTITY_INSERT Template_Group OFF
	END
	ELSE
	BEGIN
		UPDATE	Template_Group
		SET		HelpText = @HelpText,
				AllowPreview = @AllowPreview,
				PostGenerateText = @PostGenerateText,
				UpdateDocumentFields = @UpdateDocumentFields,
				EnforceValidation = @EnforceValidation,
				WizardFinishText = @WizardFinishText,
				EnforcePublishPeriod = @EnforcePublishPeriod,
				PublishStartDate = @PublishStartDate,
				PublishFinishDate = @PublishFinishDate,
				HideNavigationPane = @HideNavigationPane,
				Template_Guid = @ProjectGuid,
				Layout_Guid = @LayoutGuid,
				Template_Version = @ProjectVersion,
				Layout_Version = @LayoutVersion,
				Folder_Guid = @FolderGuid,
				ShowFormActivity = @ShowFormActivity,
				MatchProjectVersion = @MatchProjectVersion
		WHERE	Template_Group_Guid = @ProjectGroupGuid;
	END 
GO
ALTER PROCEDURE [dbo].[spProject_UpdateDefinition] (
	@Xtf xml,
	@TemplateGuid uniqueidentifier,
	@EncryptedXtf varbinary(MAX)
)
AS
	SET ARITHABORT ON

	DECLARE @FeatureFlags int;
	DECLARE @DataObjectGuid uniqueidentifier;
	DECLARE @XtfVersion nvarchar(10)

	BEGIN TRAN
		-- Feature detection --
		SET @FeatureFlags = 0
		SELECT @XtfVersion = Template.Template_Version FROM Template WHERE Template.Template_Guid = @TemplateGuid

		-- Workflow
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/Workflow/State/Transition)') as ProjectXML(P))
		BEGIN
			--Looking for a specified transition from the start state
			IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/Workflow/State)') as StateXML(S)
					  CROSS APPLY S.nodes('(Transition)') as TransitionXML(T)
					  WHERE S.value('@ID', 'uniqueidentifier') = cast('11111111-1111-1111-1111-111111111111' as uniqueidentifier)
					  AND (T.value('@SendToType', 'int') = 0 or T.value('@SendToType', 'int') IS NULL))
			BEGIN
				SET @FeatureFlags = @FeatureFlags | 256;
			END
			ELSE
			BEGIN
				SET @FeatureFlags = @FeatureFlags | 1;
			END
		END

		-- Data source
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 2		-- Data field
						OR Q.value('@TypeId', 'int') = 9	-- Data table
						OR Q.value('@TypeId', 'int') = 12	-- Data list
						OR Q.value('@TypeId', 'int') = 14)	-- Data source
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 2;

			INSERT INTO Xtf_Datasource_Dependency(Template_Guid, Template_Version, Data_Object_Guid)
			SELECT DISTINCT @TemplateGuid,
					@XtfVersion,
					Q.value('@DataObjectGuid', 'uniqueidentifier')
			FROM 
				@Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup/Question)') as QuestionXML(Q)
			WHERE Q.value('@DataObjectGuid', 'uniqueidentifier') is not null
				AND (SELECT  COUNT(*)
				FROM    Xtf_Datasource_Dependency 
				WHERE   Template_Guid = @TemplateGuid
				AND     Template_Version = @XtfVersion 
				AND		Data_Object_Guid = Q.value('@DataObjectGuid', 'uniqueidentifier')) = 0
			
		END

		-- Content library
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 11
						AND Q.value('@DisplayType', 'int') = 8) -- Existing content item
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 4;
		END
		
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 11
						AND Q.value('@DisplayType', 'int') = 4) -- Search
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 8;
		END

		BEGIN
			DELETE FROM Xtf_ContentLibrary_Dependency
			WHERE	Xtf_ContentLibrary_Dependency.Template_Guid = @TemplateGuid AND
					Xtf_ContentLibrary_Dependency.Template_Version = @XtfVersion;

			INSERT INTO Xtf_ContentLibrary_Dependency(Template_Guid, Template_Version, Content_Object_Guid)
			SELECT DISTINCT @TemplateGuid, @XtfVersion, Content_Object_Guid
			FROM (
				SELECT C.value('@Id', 'uniqueidentifier') as Content_Object_Guid
				FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup/Question/Answer/ContentItem)') as ContentItemXML(C)
				UNION
				SELECT Q.value('@ContentItemGuid', 'uniqueidentifier')
				FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup/Question)') as QuestionXML(Q)
				WHERE Q.value('@ContentItemGuid', 'uniqueidentifier') is not null) Content
		END

		-- Address
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 1)
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 16;
		END

		-- Rich text
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 19)
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 64;
		END
			
		-- Custom Question
		IF EXISTS(SELECT 1 FROM @Xtf.nodes('(/Intelledox_TemplateFile/WizardInfo/BookmarkGroup)') as ProjectXML(P)
						CROSS APPLY P.nodes('(Question)') as QuestionXML(Q)
				WHERE	Q.value('@TypeId', 'int') = 22)
		BEGIN
			SET @FeatureFlags = @FeatureFlags | 128;
		END
					
		IF @EncryptedXtf IS NULL
		BEGIN
			UPDATE	Template 
			SET		Project_Definition = @XTF,
					FeatureFlags = @FeatureFlags,
					EncryptedProjectDefinition = NULL
			WHERE	Template_Guid = @TemplateGuid;
		END
		ELSE
		BEGIN
			UPDATE	Template 
			SET		EncryptedProjectDefinition = @EncryptedXtf,
					FeatureFlags = @FeatureFlags,
					Project_Definition = NULL
			WHERE	Template_Guid = @TemplateGuid;
		END

		EXEC spProjectGroup_UpdateFeatureFlags @ProjectGuid=@TemplateGuid;
	COMMIT
GO
ALTER TABLE Template
	DROP COLUMN Content_Bookmark
GO
ALTER TABLE Template
	DROP COLUMN Fax_Template_Id
GO
ALTER procedure [dbo].[spProject_UpdateProject]
	@BusinessUnitGuid uniqueidentifier,
	@Name nvarchar(100),
	@ProjectGuid uniqueidentifier,
	@ProjectTypeID int,
	@SupplierGuid uniqueidentifier,
	@NextVersion nvarchar(10) = '0',
	@UserGuid uniqueidentifier = NULL,
	@Comment nvarchar(MAX) = NULL
as
	BEGIN TRAN

		IF NOT EXISTS(SELECT Template_Guid FROM Template WHERE Template_Guid = @ProjectGuid)
		BEGIN
			INSERT INTO Template(Business_Unit_Guid, Name, Template_Guid, 
				Template_Type_Id, Supplier_Guid, Template_Version, IsMajorVersion, Comment)
			VALUES (@BusinessUnitGuid, @Name, @ProjectGuid, 
				@ProjectTypeId, @SupplierGuid, '0.0', 0, @Comment);
		END
		ELSE
		BEGIN
		
			IF @UserGuid IS NOT NULL
			BEGIN
				EXEC spProject_AddNewProjectVersion @ProjectGuid, @NextVersion;
			END
		
			UPDATE	Template
			SET		[name] = @Name, 
					Template_type_id = @ProjectTypeID, 
					Supplier_GUID = @SupplierGuid
			WHERE	Template_Guid = @ProjectGuid;
		END

		IF @UserGuid IS NOT NULL
		BEGIN
			UPDATE Template
			SET Modified_Date = getUTCdate(),
				Modified_By = @UserGuid,
				Template_Version = @NextVersion,
				Comment = @Comment,
				IsMajorVersion = 0
			WHERE Template_Guid = @ProjectGuid;
		END
	
	COMMIT
GO
ALTER PROCEDURE [dbo].[spSync_Project]
	@TemplateID int,
	@Name nvarchar(100),
	@TemplateTypeID int,
	@TemplateGuid uniqueidentifier,
	@TemplateVersion nvarchar(10),
	@ImportDate datetime,
	@HelpText nvarchar(4000),
	@BusinessUnitGuid uniqueidentifier,
	@SupplierGuid uniqueidentifier,
	@ProjectDefinition xml,
	@ModifiedDate datetime,
	@ModifiedBy uniqueidentifier,
	@Comment nvarchar(max),
	@LockedByUserGuid uniqueidentifier,
	@IsMajorVersion bit,
	@FeatureFlags int,
	@EncryptedProjectDefinition varbinary(max) 
AS
BEGIN TRAN

	IF NOT EXISTS(SELECT Template_ID FROM Template WHERE Template_Guid = @TemplateGuid)
	BEGIN
		SET IDENTITY_INSERT Template ON
		INSERT INTO Template (Template_ID,Name,Template_Type_ID,
			Template_Guid,Template_Version,
			Import_Date,HelpText,Business_Unit_GUID,Supplier_Guid,Project_Definition,Modified_Date,Modified_By,
			Comment,LockedByUserGuid,IsMajorVersion,FeatureFlags,EncryptedProjectDefinition)
		VALUES (@TemplateID,
				@Name,
				@TemplateTypeID,
				@TemplateGuid,
				@TemplateVersion,
				@ImportDate,
				@HelpText,
				@BusinessUnitGuid,
				@SupplierGuid,
				@ProjectDefinition,
				@ModifiedDate,
				@ModifiedBy,
				@Comment,
				@LockedByUserGuid,
				@IsMajorVersion,
				@FeatureFlags,
				@EncryptedProjectDefinition)
			
		SET IDENTITY_INSERT Template OFF
	END
	ELSE
	BEGIN
		UPDATE Template
		SET Name = @Name,
			Template_Type_ID = @TemplateTypeID,
			Template_Version = @TemplateVersion,
			Import_Date = @ImportDate,
			HelpText = @HelpText,
			Supplier_Guid = @SupplierGuid,
			Project_Definition = @ProjectDefinition,
			Modified_Date = @ModifiedDate,
			Modified_By = @ModifiedBy,
			Comment = @Comment,
			LockedByUserGuid = @LockedByUserGuid,
			IsMajorVersion = @IsMajorVersion,
			FeatureFlags = @FeatureFlags,
			EncryptedProjectDefinition = @EncryptedProjectDefinition
		WHERE Template_Guid = @TemplateGuid
	END
COMMIT TRAN
GO
ALTER procedure [dbo].[spProject_ProjectList]
	@UserGuid uniqueidentifier,
	@GroupGuid uniqueidentifier,
	@ProjectTypeId int,
	@SearchString nvarchar(100),
	@Purpose nvarchar(10)
as
	declare @IsGlobal bit
	declare @BusinessUnitGUID uniqueidentifier

	SELECT	@BusinessUnitGUID = Business_Unit_GUID
	FROM	Intelledox_User
	WHERE	User_Guid = @UserGuid;

	IF EXISTS(SELECT	vwUserPermissions.*
		FROM	vwUserPermissions
		WHERE	((@Purpose = 'Design' AND vwUserPermissions.CanDesignProjects = 1)
					OR (@Purpose = 'Publish' AND vwUserPermissions.CanPublishProjects = 1))
				AND vwUserPermissions.GroupGuid IS NULL
				AND vwUserPermissions.UserGuid = @UserGuid)
	BEGIN
		SET @IsGlobal = 1;
	END

	if @GroupGuid IS NULL
	begin
		--all usergroups
		SELECT 	a.template_id, a.[name] as project_name, a.template_type_id, 
				a.template_guid, a.template_version, a.import_date, 
				a.Business_Unit_GUID, a.Supplier_Guid, a.Modified_Date, Intelledox_User.Username,
				a.Modified_By, lockedByUser.Username AS LockedBy,
				a.FeatureFlags
		FROM	Template a
			LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = a.Modified_By
			LEFT JOIN Intelledox_User lockedByUser ON lockedByUser.User_Guid = a.LockedByUserGuid
		WHERE	(@IsGlobal = 1 or a.Template_Guid in (
				SELECT	User_Group_Template.TemplateGuid
				FROM	vwUserPermissions
						INNER JOIN Intelledox_User ON vwUserPermissions.UserGuid = Intelledox_User.User_Guid
						INNER JOIN User_Group_Subscription ON Intelledox_User.User_Guid = User_Group_Subscription.UserGuid
						INNER JOIN User_Group ON vwUserPermissions.GroupGuid = User_Group.Group_Guid
						INNER JOIN User_Group_Template ON User_Group_Subscription.GroupGuid = User_Group_Template.GroupGuid
				WHERE	((@Purpose = 'Design' AND vwUserPermissions.CanDesignProjects = 1)
					OR (@Purpose = 'Publish' AND vwUserPermissions.CanPublishProjects = 1))
			AND Intelledox_User.User_Guid = @UserGuid
				))
			AND (a.Business_Unit_GUID = @BusinessUnitGUID) 
			AND a.Name COLLATE Latin1_General_CI_AI LIKE (@SearchString + '%') COLLATE Latin1_General_CI_AI
			AND (a.Template_Type_Id = @ProjectTypeId OR @ProjectTypeId = 0)
		ORDER BY a.[name];
	end
	else
	begin
		--specific user group
		SELECT 	a.template_id, a.[name] as project_name, a.template_type_id,
				a.template_guid, a.template_version, a.import_date, 
				a.Business_Unit_GUID, a.Supplier_Guid, a.Modified_Date, Intelledox_User.Username,
				a.Modified_By, lockedByUser.Username AS LockedBy,
				a.FeatureFlags
		FROM	Template a
				INNER JOIN User_Group_Template d on a.Template_Guid = d.TemplateGuid
				INNER JOIN User_Group ON d.GroupGuid = User_Group.Group_Guid AND User_Group.Group_Guid = @GroupGuid
				LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = a.Modified_By
				LEFT JOIN Intelledox_User lockedByUser ON lockedByUser.User_Guid = a.LockedByUserGuid
		WHERE	(@IsGlobal = 1 or a.template_Guid in (
				SELECT	User_Group_Template.TemplateGuid
				FROM	vwUserPermissions
						INNER JOIN Intelledox_User ON vwUserPermissions.UserGuid = Intelledox_User.User_Guid
						INNER JOIN User_Group_Subscription ON Intelledox_User.User_Guid = User_Group_Subscription.UserGuid
						INNER JOIN User_Group ON vwUserPermissions.GroupGuid = User_Group.Group_Guid
						INNER JOIN User_Group_Template ON User_Group_Subscription.GroupGuid = User_Group_Template.GroupGuid
				WHERE	((@Purpose = 'Design' AND vwUserPermissions.CanDesignProjects = 1)
					OR (@Purpose = 'Publish' AND vwUserPermissions.CanPublishProjects = 1))
			))
			and (a.Business_Unit_GUID = @BusinessUnitGUID) 
			AND a.Name COLLATE Latin1_General_CI_AI LIKE (@SearchString + '%') COLLATE Latin1_General_CI_AI
			AND (a.Template_Type_Id = @ProjectTypeId OR @ProjectTypeId = 0)
		ORDER BY a.[name];
	end
GO
ALTER procedure [dbo].[spProject_GetProjectsByContentItem]
	@ContentGuid varchar(40),
	@BusinessUnitGuid uniqueidentifier
as
	SET ARITHABORT ON 

	SELECT 	Template.template_id, 
			Template.[name] as project_name, 
			Template.template_type_id, 
			Template.template_guid, 
			Template.template_version, 
			Template.import_date,
			Template.Business_Unit_GUID, 
			Template.Supplier_Guid,
			Template.Modified_Date,
			Intelledox_User.Username,
			Template.Modified_By,
			Template.FeatureFlags
	FROM	Template
		LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = Template.Modified_By
		LEFT JOIN Xtf_ContentLibrary_Dependency on Xtf_ContentLibrary_Dependency.Template_Guid = Template.Template_Guid
	WHERE	Template.Business_Unit_GUID = @BusinessUnitGuid
		AND Xtf_ContentLibrary_Dependency.Content_Object_Guid = @ContentGuid 
	ORDER BY Template.[name];
GO
ALTER procedure [dbo].[spProject_ProjectListFullText]
	@UserGuid uniqueidentifier,
	@GroupGuid uniqueidentifier,
	@ProjectTypeId int,
	@SearchString nvarchar(100),
	@FullText NVarChar(1000)
as
	declare @IsGlobal bit
	declare @BusinessUnitGUID uniqueidentifier

	SELECT	@BusinessUnitGUID = Business_Unit_GUID
	FROM	Intelledox_User
	WHERE	User_Guid = @UserGuid;

	IF EXISTS(SELECT	vwUserPermissions.*
		FROM	vwUserPermissions
		WHERE	vwUserPermissions.CanDesignProjects = 1
				AND vwUserPermissions.GroupGuid IS NULL
				AND vwUserPermissions.UserGuid = @UserGuid)
	BEGIN
		SET @IsGlobal = 1;
	END

	if @GroupGuid IS NULL
	begin
		--all usergroups
		SELECT 	a.template_id, a.[name] as project_name, a.template_type_id,
				a.template_guid, a.template_version, a.import_date, 
				a.Business_Unit_GUID, a.Supplier_Guid, a.Modified_Date, Intelledox_User.Username,
				a.Modified_By, lockedByUser.Username AS LockedBy,
				a.FeatureFlags
		FROM	Template a
				LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = a.Modified_By
				LEFT JOIN Intelledox_User lockedByUser ON lockedByUser.User_Guid = a.LockedByUserGuid
		WHERE	(@IsGlobal = 1 or a.template_Guid in (
				SELECT	User_Group_Template.TemplateGuid
				FROM	vwUserPermissions
						INNER JOIN Intelledox_User ON vwUserPermissions.UserGuid = Intelledox_User.User_Guid
						INNER JOIN User_Group_Subscription ON Intelledox_User.User_Guid = User_Group_Subscription.UserGuid
						INNER JOIN User_Group ON vwUserPermissions.GroupGuid = User_Group.Group_Guid
						INNER JOIN User_Group_Template ON User_Group_Subscription.GroupGuid = User_Group_Template.GroupGuid 
				WHERE	vwUserPermissions.CanDesignProjects = 1
			AND Intelledox_User.User_Guid = @UserGuid
				))
			AND (a.Business_Unit_GUID = @BusinessUnitGUID) 
			AND a.Name COLLATE Latin1_General_CI_AI LIKE (@SearchString + '%') COLLATE Latin1_General_CI_AI
			AND (a.Template_Type_Id = @ProjectTypeId OR @ProjectTypeId = 0)
			AND (a.Template_Guid IN (
					SELECT	Template_Guid
					FROM	Template_File tf
					WHERE	Contains(*, @FullText)
				))
		ORDER BY a.[name];
	end
	else
	begin
		--specific user group
		SELECT 	a.template_id, a.[name] as project_name, a.template_type_id,
				a.template_guid, a.template_version, a.import_date, 
				a.Business_Unit_GUID, a.Supplier_Guid, a.Modified_Date, Intelledox_User.Username,
				a.Modified_By, lockedByUser.Username AS LockedBy,
				a.FeatureFlags
		FROM	Template a
				INNER JOIN User_Group_Template d on a.Template_Guid = d.TemplateGuid
				INNER JOIN User_Group ON d.GroupGuid = User_Group.Group_Guid  AND User_Group.Group_Guid = @GroupGuid
				LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = a.Modified_By
				LEFT JOIN Intelledox_User lockedByUser ON lockedByUser.User_Guid = a.LockedByUserGuid
		WHERE	(@IsGlobal = 1 or a.template_Guid in (
				SELECT	User_Group_Template.TemplateGuid
				FROM	vwUserPermissions
						INNER JOIN Intelledox_User ON vwUserPermissions.UserGuid = Intelledox_User.User_Guid
						INNER JOIN User_Group_Subscription ON Intelledox_User.User_Guid = User_Group_Subscription.UserGuid
						INNER JOIN User_Group ON vwUserPermissions.GroupGuid = User_Group.Group_Guid
						INNER JOIN User_Group_Template ON User_Group_Subscription.GroupGuid = User_Group_Template.GroupGuid 
				WHERE	vwUserPermissions.CanDesignProjects = 1
			))
			and (a.Business_Unit_GUID = @BusinessUnitGUID) 
			AND a.Name COLLATE Latin1_General_CI_AI LIKE (@SearchString + '%') COLLATE Latin1_General_CI_AI
			AND (a.Template_Type_Id = @ProjectTypeId OR @ProjectTypeId = 0)
			AND (a.Template_Guid IN (
					SELECT	Template_Guid
					FROM	Template_File tf
					WHERE	Contains(*, @FullText)
				))
		ORDER BY a.[name];
	end
GO
ALTER procedure [dbo].[spTemplate_TemplateList]
	@TemplateGuid uniqueidentifier,
	@ErrorCode int output
AS
	SET NOCOUNT ON
	
	SELECT	a.template_id, a.[name] as template_name, a.template_type_id,
			a.template_guid, a.Supplier_Guid, a.Business_Unit_Guid,
			a.HelpText, a.Modified_Date, Intelledox_User.Username,
			a.[name] as Project_Name, a.Modified_By, lockedByUser.Username AS LockedBy, a.Comment, 
			a.Template_Version, a.FeatureFlags, a.IsMajorVersion
	FROM	Template a
			LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = a.Modified_By
			LEFT JOIN Intelledox_User lockedByUser ON lockedByUser.User_Guid = a.LockedByUserGuid
	WHERE	a.Template_Guid = @TemplateGuid;

	set @ErrorCode = @@error;
GO
ALTER PROCEDURE [dbo].[spTenant_CreateAdminUser] (
	   @TemplateBusinessUnit uniqueidentifier,
	   @AdminUserGuid uniqueidentifier,
       @FirstName nvarchar(50),
       @LastName nvarchar(50),
       @UserName nvarchar(256),
       @UserPasswordHash varchar(1000),
       @UserPwdSalt nvarchar(128),
       @UserPwdFormat int,
       @Email nvarchar(256)
)
AS
		
	DECLARE @GlobalAdminRoleGuid uniqueidentifier

	--User address for admin user
    INSERT INTO Address_Book (Full_Name, First_Name, Last_Name, Email_Address)
    VALUES (@FirstName + ' ' + @LastName, @FirstName, @LastName, @Email)

    --Admin
    INSERT INTO Intelledox_User(Username, Pwdhash, PwdSalt, PwdFormat, ChangePassword, WinNT_User, Business_Unit_Guid, User_Guid, Address_ID, IsGuest)
    VALUES (@UserName, @UserPasswordHash, @UserPwdSalt, @UserPwdFormat, 1, 0, @TemplateBusinessUnit, @AdminUserGuid, @@IDENTITY, 0)

	IF NOT EXISTS(SELECT 1 
					FROM Administrator_Level 
					WHERE AdminLevel_Description = 'Global Administrator' 
						AND Business_Unit_Guid = @TemplateBusinessUnit)
	BEGIN
		SET @GlobalAdminRoleGuid = NewId() -- We need this later
		INSERT INTO Administrator_Level(AdminLevel_Description, RoleGuid, Business_Unit_Guid)
		VALUES ('Global Administrator', @GlobalAdminRoleGuid, @TemplateBusinessUnit)
		
		INSERT INTO Role_Permission(PermissionGuid, RoleGuid)
		SELECT Permission.PermissionGuid, @GlobalAdminRoleGuid
		FROM Permission
	END
	ELSE
	BEGIN
		SELECT @GlobalAdminRoleGuid = RoleGuid  
		FROM Administrator_Level 
		WHERE AdminLevel_Description = 'Global Administrator' 
			AND Business_Unit_Guid = @TemplateBusinessUnit
	END
	
    --Make admin user a global admin (that we previously defined)
	INSERT INTO User_Role(UserGuid, RoleGuid, GroupGuid)
	VALUES(@AdminUserGuid, @GlobalAdminRoleGuid, NULL)

	--Group assignment for the admin user
    INSERT INTO User_Group_Subscription(UserGuid, IsDefaultGroup, GroupGuid)
    SELECT @AdminUserGuid, 1, Group_Guid 
    FROM User_Group
    WHERE SystemGroup = 1 
    AND Business_Unit_Guid = @TemplateBusinessUnit

GO


ALTER TABLE Data_Object
ADD Allow_Cache BIT NOT NULL DEFAULT(0),
	Cache_Duration int NOT NULL DEFAULT(0)
GO

CREATE PROCEDURE [dbo].[spGetCached_DataSourceDependencies] (
	@ProjectGuid as uniqueidentifier
)
AS
	SELECT DISTINCT Data_Object.Data_Object_Guid,
		Data_Object.Data_Object_ID,
		Data_Object.Data_Service_Guid,
		Data_Object.Data_Service_ID,
		Data_Object.Display_Name,
		Data_Object.Merge_Source,
		Data_Object.[Object_Name],
		Data_Object.Object_Type,
		Data_Object.Allow_Cache,
		Data_Object.Cache_Duration
	FROM [Data_Object]
	inner join Xtf_Datasource_Dependency ON Xtf_Datasource_Dependency.Data_Object_Guid = [Data_Object].Data_Object_Guid
	AND Xtf_Datasource_Dependency.Template_Guid = @ProjectGuid
	WHERE Data_Object.Allow_Cache = 1
GO

ALTER PROCEDURE [dbo].[spDataSource_DataObjectList]
	@DataObjectGuid uniqueidentifier = null,
	@DataServiceGuid uniqueidentifier = null
AS
	IF @DataObjectGuid IS NULL
		SELECT	o.[Object_Name], o.data_object_guid, o.data_service_guid, o.Merge_Source, 
				o.Object_Type, o.Display_Name, o.Allow_Cache, o.Cache_Duration
		FROM	data_object o
		WHERE	o.data_service_guid = @DataServiceGuid
		ORDER BY o.Display_Name;
	ELSE
		SELECT	o.[Object_Name], o.data_object_guid, o.data_service_guid, o.Merge_Source, 
				o.Object_Type, o.Display_Name, o.Allow_Cache, o.Cache_Duration
		FROM	data_object o
		WHERE	o.data_object_guid = @DataObjectGuid
		ORDER BY o.Display_Name;
GO

ALTER PROCEDURE [dbo].[spDataSource_UpdateDataObject]
	@DataObjectGuid uniqueidentifier,
	@DataServiceGuid uniqueidentifier,
	@Name nvarchar(500),
	@DisplayName nvarchar(500),
	@MergeSource bit,
	@ObjectType uniqueidentifier,
	@AllowCache bit,
	@CacheDuration int
AS
	IF NOT EXISTS(SELECT * FROM data_object WHERE Data_Object_Guid = @DataObjectGuid)
	BEGIN
		INSERT INTO data_object (Data_Service_Guid, [Object_Name], Merge_Source, 
				Data_Object_Guid, Object_Type, Display_Name, Allow_Cache, Cache_Duration)
		VALUES (@DataServiceGuid, @Name, @MergeSource, @DataObjectGuid,
				 @ObjectType, @DisplayName, @AllowCache, @CacheDuration);
	END	
	ELSE
	BEGIN		
		UPDATE	data_object
		SET		[object_name] = @Name, 
				merge_source = @MergeSource,
				Object_Type = @ObjectType,
				Display_Name = @DisplayName,
				Allow_Cache = @AllowCache,
				Cache_Duration = @CacheDuration
		WHERE	data_object_guid = @DataObjectGuid;
	END
GO

