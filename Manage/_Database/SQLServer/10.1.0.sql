truncate table dbversion;
go
insert into dbversion(dbversion) values ('10.1.0');
GO
ALTER TABLE Template_Version
	ADD Import_Date DateTime NULL
GO
ALTER PROCEDURE [dbo].[spProject_UpdateProject]
	@BusinessUnitGuid uniqueidentifier,
	@Name nvarchar(100),
	@ProjectGuid uniqueidentifier,
	@ProjectTypeID int,
	@FolderGuid uniqueidentifier,
	@SupplierGuid uniqueidentifier,
	@NextVersion nvarchar(10) = '0.0',
	@UserGuid uniqueidentifier = NULL,
	@Comment nvarchar(MAX) = NULL,
	@ImportModifiedDateUtc datetime = NULL
AS
	IF @UserGuid IS NULL
	BEGIN
		UPDATE	Template
		SET		[name] = @Name, 
				Template_type_id = @ProjectTypeID, 
				Supplier_GUID = @SupplierGuid,
				FolderGuid = @FolderGuid,
				Import_Date = @ImportModifiedDateUtc
		WHERE	Template_Guid = @ProjectGuid;
	END
	ELSE
	BEGIN
		IF NOT EXISTS(SELECT Template_Guid FROM Template WHERE Template_Guid = @ProjectGuid)
		BEGIN
			INSERT INTO Template(Business_Unit_Guid, Name, Template_Guid, 
				Template_Type_Id, FolderGuid, Supplier_Guid, Template_Version, IsMajorVersion, Comment,
				Modified_Date, Modified_By, Import_Date)
			VALUES (@BusinessUnitGuid, @Name, @ProjectGuid, 
				@ProjectTypeId, @FolderGuid, @SupplierGuid, @NextVersion, 0, @Comment,
				GetUtcDate(), @UserGuid, @ImportModifiedDateUtc);
		END
		ELSE
		BEGIN
			BEGIN TRAN
				EXEC spProject_AddNewProjectVersion @ProjectGuid, @BusinessUnitGuid;
		
				UPDATE	Template
				SET		[name] = @Name, 
						Template_type_id = @ProjectTypeID, 
						FolderGuid = @FolderGuid,
						Supplier_GUID = @SupplierGuid,
						Modified_Date = GetUtcDate(),
						Modified_By = @UserGuid,
						Template_Version = @NextVersion,
						Comment = @Comment,
						IsMajorVersion = 0,
						Import_Date = @ImportModifiedDateUtc
				WHERE	Template_Guid = @ProjectGuid;
			COMMIT
		
			EXEC spProject_DeleteOldProjectVersion @ProjectGuid=@ProjectGuid, 
				@NextVersion=@NextVersion,
				@BusinessUnitGuid=@BusinessUnitGuid;
		END
	END
GO
ALTER VIEW [dbo].[vwTemplateVersion]
AS
	SELECT	Template_Version.Template_Version, 
			Template_Version.Template_Guid,
			Template_Version.Modified_Date,
			Template_Version.Modified_By,
			Template_Version.Comment,
			Template.Template_Type_ID,
			Template.LockedByUserGuid,
			Template_Version.IsMajorVersion,
			Template_Version.FeatureFlags,
			Template_Version.Import_Date,
			Intelledox_User.Username,
			Address_Book.First_Name + ' ' + Address_Book.Last_Name AS Full_Name,
			CASE (SELECT COUNT(*)
					FROM Template_Group 
					WHERE (Template_Group.Template_Guid = Template_Version.Template_Guid
								AND Template_Group.Template_Version = Template_Version.Template_Version)
							OR (Template_Group.Layout_Guid = Template_Version.Template_Guid
								AND Template_Group.Layout_Version = Template_Version.Template_Version)) 
				WHEN 0
				THEN 0
				ELSE 1
			END AS InUse,
			0 AS Latest
		FROM	Template_Version
			INNER JOIN Template ON Template_Version.Template_Guid = Template.Template_Guid
			LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = Template_Version.Modified_By
			LEFT JOIN Address_Book ON Intelledox_User.Address_ID = Address_Book.Address_ID
	UNION ALL
		SELECT	Template.Template_Version, 
				Template.Template_Guid,
				Template.Modified_Date,
				Template.Modified_By,
				Template.Comment,
				Template.Template_Type_ID,
				Template.LockedByUserGuid,
				Template.IsMajorVersion,
				Template.FeatureFlags,
				Template.Import_Date,
				Intelledox_User.Username,
				Address_Book.First_Name + ' ' + Address_Book.Last_Name AS Full_Name,
				CASE (SELECT COUNT(*)
						FROM Template_Group 
						WHERE (Template_Group.Template_Guid = Template.Template_Guid
									AND (Template_Group.Template_Version = Template.Template_Version OR ISNULL(Template_Group.Template_Version, '0') = '0'))
							OR (Template_Group.Layout_Guid = Template.Template_Guid
									AND (Template_Group.Layout_Version = Template.Template_Version OR ISNULL(Template_Group.Layout_Version, '0') = '0')))
					WHEN 0
					THEN 0
					ELSE 1
				END AS InUse,
				1 AS Latest
		FROM	Template
			LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = Template.Modified_By
			LEFT JOIN Address_Book ON Intelledox_User.Address_ID = Address_Book.Address_ID;
GO
ALTER procedure [dbo].[spProject_GetProjectVersions]
	@ProjectGuid uniqueidentifier
as
		SELECT vwTemplateVersion.Template_Version, 
			vwTemplateVersion.Template_Guid,
			vwTemplateVersion.Modified_Date,
			vwTemplateVersion.Modified_By,
			vwTemplateVersion.Username,
			ISNULL(vwTemplateVersion.Full_Name, '') AS Full_Name,
			vwTemplateVersion.Comment,
			vwTemplateVersion.LockedByUserGuid,
			vwTemplateVersion.FeatureFlags,
			vwTemplateVersion.IsMajorVersion,
			vwTemplateVersion.InUse,
			vwTemplateVersion.Import_Date
		FROM	vwTemplateVersion
		WHERE	vwTemplateVersion.Template_Guid = @ProjectGuid
	ORDER BY Modified_Date DESC;
GO
ALTER procedure [dbo].[spProject_AddNewProjectVersion]
	@ProjectGuid uniqueidentifier,
	@BusinessUnitGuid uniqueidentifier
AS
	BEGIN TRAN

		SET NOCOUNT ON

		INSERT INTO Template_Version 
			(Template_Version, 
			Template_Guid, 
			Modified_Date, 
			Modified_By,
			Project_Definition,
			Comment,
			IsMajorVersion,
			FeatureFlags,
			EncryptedProjectDefinition,
			Import_Date)
		SELECT Template.Template_Version,
			Template.Template_Guid,
			Template.Modified_Date,
			Template.Modified_By,
			Template.Project_Definition,
			Template.Comment,
			Template.IsMajorVersion,
			Template.FeatureFlags,
			Template.EncryptedProjectDefinition,
			Template.Import_Date
		FROM Template
		WHERE Template.Template_Guid = @ProjectGuid;
		
		INSERT INTO Template_File_Version (Template_Guid, File_Guid, Template_Version, [Binary],
				FormatTypeId)
		SELECT	Template.Template_Guid, Template_File.File_Guid, Template.Template_Version, 
				Template_File.[Binary], Template_File.FormatTypeId
		FROM	Template
				INNER JOIN Template_File ON Template.Template_Guid = Template_File.Template_Guid
		WHERE	Template.Template_Guid = @ProjectGuid;
	COMMIT
GO
ALTER procedure [dbo].[spProject_RestoreVersion]
	@ProjectGuid uniqueidentifier,
	@VersionNumber nvarchar(10),
	@UserGuid uniqueidentifier,
	@RestoreVersionComment nvarchar(50),
	@NextVersion nvarchar(10)
as
	SET NOCOUNT ON

	BEGIN TRAN	
		DECLARE @BusinessUnitGuid uniqueidentifier;

		SELECT TOP 1 @BusinessUnitGuid = Business_Unit_Guid 
		FROM Template
		WHERE Template_Guid = @ProjectGuid;
	
		INSERT INTO Template_Version 
			(Template_Version, 
			Template_Guid, 
			Modified_Date, 
			Modified_By,
			Project_Definition,
			Comment,
			IsMajorVersion,
			FeatureFlags,
			EncryptedProjectDefinition,
			Import_Date)
		SELECT Template.Template_Version,
			Template.Template_Guid,
			Template.Modified_Date,	
			Template.Modified_By,
			Template.Project_Definition,
			Template.Comment,
			Template.IsMajorVersion,
			Template.FeatureFlags,
			Template.EncryptedProjectDefinition,
			Template.Import_Date
		FROM Template
		WHERE Template.Template_Guid = @ProjectGuid;
			
		INSERT INTO Template_File_Version (Template_Guid, File_Guid, Template_Version, [Binary],
				FormatTypeId)
		SELECT	Template.Template_Guid, Template_File.File_Guid, Template.Template_Version, 
				Template_File.[Binary], Template_File.FormatTypeId
		FROM	Template
				INNER JOIN Template_File ON Template.Template_Guid = Template_File.Template_Guid
		WHERE	Template.Template_Guid = @ProjectGuid;
		
		UPDATE	Template
		SET		Project_Definition = Template_Version.Project_Definition, 
				Template_Version = @NextVersion, 
				Comment = @RestoreVersionComment,
				Modified_Date = GetUTCdate(),
				Modified_By = @UserGuid,
				IsMajorVersion = 1,
				FeatureFlags = Template_Version.FeatureFlags,
				EncryptedProjectDefinition = Template_Version.EncryptedProjectDefinition,
				Import_Date = Template_Version.Import_Date
		FROM	Template
				INNER JOIN Template_Version ON Template.Template_Guid = Template_Version.Template_Guid
		WHERE	Template_Version.Template_Guid = @ProjectGuid
				AND Template_Version.Template_Version = @VersionNumber
		
		DELETE FROM Template_File
		WHERE	Template_Guid = @ProjectGuid;
		
		INSERT INTO Template_File(Template_Guid, File_Guid, [Binary], FormatTypeId)
		SELECT	@ProjectGuid, Template_File_Version.File_Guid, Template_File_Version.[Binary],
				Template_File_Version.FormatTypeId
		FROM	Template_File_Version 
		WHERE	Template_Guid = @ProjectGuid 
				AND Template_Version = @VersionNumber; 
		
		--copy over dependencies from the source version
		INSERT INTO Xtf_ContentLibrary_Dependency(Template_Guid, Template_Version, Content_Object_Guid, Display_Type)
		SELECT	Template_Guid, @NextVersion, Content_Object_Guid, Display_Type
		FROM	Xtf_ContentLibrary_Dependency
		WHERE	Template_Guid = @ProjectGuid 
				AND Template_Version = @VersionNumber;
				
		INSERT INTO Xtf_Datasource_Dependency(Template_Guid, Template_Version, Data_Object_Guid)
		SELECT	Template_Guid, @NextVersion, Data_Object_Guid
		FROM	Xtf_Datasource_Dependency
		WHERE	Template_Guid = @ProjectGuid 
				AND Template_Version = @VersionNumber;
				
		INSERT INTO Xtf_Fragment_Dependency(Template_Guid, Template_Version, Fragment_Guid)
		SELECT	Template_Guid, @NextVersion, Fragment_Guid
		FROM	Xtf_Fragment_Dependency
		WHERE	Template_Guid = @ProjectGuid 
				AND Template_Version = @VersionNumber;
	COMMIT

	EXEC spProjectGroup_UpdateFeatureFlags @ProjectGuid=@ProjectGuid;

	EXEC spProject_DeleteOldProjectVersion @ProjectGuid=@ProjectGuid, 
		@NextVersion=@NextVersion,
		@BusinessUnitGuid=@BusinessUnitGuid;
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
			a.Template_Version, a.FeatureFlags, a.IsMajorVersion, a.FolderGuid,
			a.Import_Date
	FROM	Template a
			LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = a.Modified_By
			LEFT JOIN Intelledox_User lockedByUser ON lockedByUser.User_Guid = a.LockedByUserGuid
	WHERE	a.Template_Guid = @TemplateGuid;

	SET @ErrorCode = @@error;
GO
CREATE PROCEDURE [dbo].[spContent_GetVersionDetails] (
	@UniqueId as uniqueidentifier
)
AS
	SELECT	cd.ContentData_Version, cd.Modified_Date
	FROM	ContentData_Binary cd
			INNER JOIN Content_Item ON cd.ContentData_Guid = Content_Item.ContentData_Guid
	WHERE	Content_Item.ContentItem_Guid = @UniqueId
	UNION
	SELECT	ct.ContentData_Version, ct.Modified_Date
	FROM	ContentData_Text ct
			INNER JOIN Content_Item ON ct.ContentData_Guid = Content_Item.ContentData_Guid
	WHERE	Content_Item.ContentItem_Guid = @UniqueId
GO
ALTER TABLE ContentData_Binary
	ADD Import_Date DateTime NULL
GO
ALTER TABLE ContentData_Text
	ADD Import_Date DateTime NULL
GO
ALTER TABLE ContentData_Binary_Version
	ADD Import_Date DateTime NULL
GO
ALTER TABLE ContentData_Text_Version
	ADD Import_Date DateTime NULL
GO
ALTER PROCEDURE [dbo].[spLibrary_UpdateBinary] (
	@UniqueId as uniqueidentifier,
	@ContentData as image,
	@Extension as varchar(5),
	@UserGuid as uniqueidentifier,
	@VersionComment as nvarchar(max),
	@Version as int,
	@ImportDate as DateTime
)
AS
	DECLARE @ContentData_Guid uniqueidentifier;
	DECLARE @ContentItem_Guid uniqueidentifier;
	DECLARE @BusinessUnitGuid uniqueidentifier;
	DECLARE @Approvals nvarchar(10);
	DECLARE @MaxVersion int;
	DECLARE @CIApproved int;

	SET NOCOUNT ON;

	SELECT	@ContentData_Guid = ContentData_Guid, 
			@ContentItem_Guid = ContentItem_Guid,
			@BusinessUnitGuid = Business_Unit_Guid,
			@CIApproved = Approved
	FROM	Content_Item
	WHERE	ContentItem_Guid = @UniqueId;
	
	SELECT	@Approvals = OptionValue
	FROM	Global_Options
	WHERE	OptionCode = 'REQUIRE_CONTENT_APPROVAL'
			AND BusinessUnitGuid = @BusinessUnitGuid;


	IF (@Approvals = 'true')
	BEGIN
		IF @ContentData_Guid IS NULL OR NOT EXISTS(SELECT ContentData_Guid 
												FROM ContentData_Binary 
												WHERE	ContentData_Guid = @ContentData_Guid)
		BEGIN
			SET	@ContentData_Guid = newid();
			
			INSERT INTO ContentData_Binary(ContentData_Guid, ContentData, FileType, ContentData_Version, Modified_Date, Modified_By, VersionComment, Import_Date)
			VALUES (@ContentData_Guid, @ContentData, @Extension, CASE WHEN @Version IS NULL THEN 1 ELSE @Version END, getUTCdate(), @UserGuid, @VersionComment, @ImportDate);

			UPDATE	Content_Item
			SET		ContentData_Guid = @ContentData_Guid,
					Approved = 0
			WHERE	ContentItem_Guid = @UniqueId;
		END
		ELSE
		BEGIN
			IF (@CIApproved = 0)
			BEGIN
				-- Content item hasnt been approved yet so we can replace it
				EXEC spLibrary_AddNewLibraryVersion @ContentData_Guid, 1, @UniqueId;
				
				UPDATE	ContentData_Binary
				SET		ContentData = @ContentData,
						FileType = @Extension,
						Modified_Date = getUTCdate(),
						Modified_By = @UserGuid,
						ContentData_Version = CASE WHEN @Version IS NULL THEN ContentData_Version + 1 ELSE @Version END,
						VersionComment = @VersionComment,
						Import_Date = @ImportDate
				WHERE	ContentData_Guid = @ContentData_Guid;

				-- Expire old unapproved versions
				UPDATE	ContentData_Binary_Version
				SET		Approved = 1
				WHERE	ContentData_Guid = @ContentData_Guid
						AND Approved = 0;
			END
			ELSE
			BEGIN
				SELECT	@MaxVersion = MAX(ContentData_Version)
				FROM	(SELECT ContentData_Version
						FROM	ContentData_Binary_Version
						WHERE	ContentData_Guid = @ContentData_Guid
						UNION
						SELECT	ContentData_Version
						FROM	ContentData_Binary
						WHERE	ContentData_Guid = @ContentData_Guid) Versions

				-- Expire old unapproved versions
				UPDATE	ContentData_Binary_Version
				SET		Approved = 1
				WHERE	ContentData_Guid = @ContentData_Guid
						AND Approved = 0;
			
				-- Insert new unapproved version
				INSERT INTO ContentData_Binary_Version(ContentData_Guid, ContentData, FileType, ContentData_Version, Modified_Date, Modified_By, Approved, VersionComment, Import_Date)
				VALUES (@ContentData_Guid, @ContentData, @Extension, CASE WHEN @Version IS NULL THEN IsNull(@MaxVersion, 0) + 1 ELSE @Version END, getUTCdate(), @UserGuid, 0, @VersionComment, @ImportDate);
			END
				
			IF (SELECT COUNT(*)
				FROM	Template
					INNER JOIN Template_Group ON Template_Group.Layout_Guid = Template.Template_Guid OR Template_Group.Template_Guid = Template.Template_Guid
					INNER JOIN Xtf_ContentLibrary_Dependency on Xtf_ContentLibrary_Dependency.Template_Guid = Template.Template_Guid
				WHERE	Template_Group.MatchProjectVersion = 1
						AND Xtf_ContentLibrary_Dependency.Content_Object_Guid = @ContentData_Guid) = 0
			BEGIN
				EXEC spLibrary_ClearExcessVersions @ContentData_Guid, 0;
			END
			
		END
	END
	ELSE
	BEGIN
		IF EXISTS(SELECT ContentData_Guid FROM ContentData_Binary WHERE ContentData_Guid = @ContentData_Guid)
		BEGIN
			EXEC spLibrary_AddNewLibraryVersion @ContentData_Guid, 1, @UniqueId;
			
			UPDATE	ContentData_Binary
			SET		ContentData = @ContentData,
					FileType = @Extension,
					VersionComment = @VersionComment,
					Import_Date = @ImportDate
			WHERE	ContentData_Guid = @ContentData_Guid;
		END
		ELSE
		BEGIN
			IF @ContentItem_Guid IS NOT NULL
			BEGIN
				SET	@ContentData_Guid = newid();

				INSERT INTO ContentData_Binary(ContentData_Guid, ContentData, FileType, ContentData_Version, VersionComment, Import_Date)
				VALUES (@ContentData_Guid, @ContentData, @Extension, CASE WHEN @Version IS NULL THEN 1 ELSE @Version END, @VersionComment, @ImportDate);

				UPDATE	Content_Item
				SET		ContentData_Guid = @ContentData_Guid
				WHERE	ContentItem_Guid = @UniqueId;
			END
		END
		
		IF @UserGuid IS NOT NULL
		BEGIN
			UPDATE	ContentData_Binary
			SET		Modified_Date = getUTCdate(),
					Modified_By = @UserGuid,
					ContentData_Version = CASE WHEN @Version IS NULL THEN ContentData_Version + 1 ELSE @Version END,
					VersionComment = @VersionComment,
					Import_Date = @ImportDate
			WHERE	ContentData_Guid = @ContentData_Guid;
		END
	END

	DELETE	FROM Content_Item_Placeholder
	WHERE	ContentItemGuid = @ContentItem_Guid;
	
	UPDATE	Content_Item
	SET		IsIndexed = 0
	WHERE	ContentItem_Guid = @ContentItem_Guid;

GO
ALTER PROCEDURE [dbo].[spLibrary_UpdateText] (
	@UniqueId as uniqueidentifier,
	@ContentData as nvarchar(max),
	@UserGuid as uniqueidentifier,
	@VersionComment as nvarchar(max),
	@Version as int,
	@ImportDate as DateTime
)
AS
	DECLARE @ContentData_Guid uniqueidentifier;
	DECLARE @BusinessUnitGuid uniqueidentifier;
	DECLARE @Approvals nvarchar(10);
	DECLARE @MaxVersion int;

	SELECT	@ContentData_Guid = ContentData_Guid,
			@BusinessUnitGuid = Business_Unit_Guid
	FROM	Content_Item
	WHERE	ContentItem_Guid = @UniqueId
	
	SELECT	@Approvals = OptionValue
	FROM	Global_Options
	WHERE	OptionCode = 'REQUIRE_CONTENT_APPROVAL'
			AND BusinessUnitGuid = @BusinessUnitGuid;


	IF (@Approvals = 'true')
	BEGIN
		IF @ContentData_Guid IS NULL OR NOT EXISTS(SELECT ContentData_Guid 
												FROM ContentData_Text 
												WHERE	ContentData_Guid = @ContentData_Guid)
		BEGIN
			SET	@ContentData_Guid = newid();
			
			INSERT INTO ContentData_Text(ContentData_Guid, ContentData, ContentData_Version, Modified_Date, Modified_By, VersionComment, Import_Date)
			VALUES (@ContentData_Guid, @ContentData, CASE WHEN @Version IS NULL THEN 1 ELSE @Version END, getUTCdate(), @UserGuid, @VersionComment, @ImportDate)

			UPDATE	Content_Item
			SET		ContentData_Guid = @ContentData_Guid,
					Approved = 0
			WHERE	ContentItem_Guid = @UniqueId;
		END
		ELSE
		BEGIN
			SELECT	@MaxVersion = MAX(ContentData_Version)
			FROM	(SELECT ContentData_Version
					FROM	ContentData_Text_Version
					WHERE	ContentData_Guid = @ContentData_Guid
					UNION
					SELECT	ContentData_Version
					FROM	ContentData_Text
					WHERE	ContentData_Guid = @ContentData_Guid) Versions

			-- Expire old unapproved versions
			UPDATE	ContentData_Text_Version
			SET		Approved = 1
			WHERE	ContentData_Guid = @ContentData_Guid
					AND Approved = 0;
		
			-- Insert new unapproved version
			INSERT INTO ContentData_Text_Version(ContentData_Guid, ContentData, ContentData_Version, Modified_Date, Modified_By, Approved, VersionComment, Import_Date)
			VALUES (@ContentData_Guid, @ContentData, CASE WHEN @Version IS NULL THEN IsNull(@MaxVersion, 0) + 1 ELSE @Version END, getUTCdate(), @UserGuid, 0, @VersionComment, @ImportDate);
			
			IF (SELECT COUNT(*)
				FROM	Template
					INNER JOIN Template_Group ON Template_Group.Layout_Guid = Template.Template_Guid OR Template_Group.Template_Guid = Template.Template_Guid
					INNER JOIN Xtf_ContentLibrary_Dependency on Xtf_ContentLibrary_Dependency.Template_Guid = Template.Template_Guid
				WHERE	Template_Group.MatchProjectVersion = 1
						AND Xtf_ContentLibrary_Dependency.Content_Object_Guid = @UniqueId) = 0
			BEGIN
				EXEC spLibrary_ClearExcessVersions @ContentData_Guid, 0;
			END
		END
	END
	ELSE
	BEGIN
		IF EXISTS(SELECT ContentData_Guid FROM ContentData_Text WHERE ContentData_Guid = @ContentData_Guid)
		BEGIN
			EXEC spLibrary_AddNewLibraryVersion @ContentData_Guid, 0, @UniqueId;
			
			UPDATE	ContentData_Text
			SET		ContentData = @ContentData,
					VersionComment = @VersionComment,
					Import_Date = @ImportDate
			WHERE	ContentData_Guid = @ContentData_Guid
		END
		ELSE
		BEGIN
			SET	@ContentData_Guid = newid()

			INSERT INTO ContentData_Text(ContentData_Guid, ContentData, ContentData_Version, VersionComment, Import_Date)
			VALUES (@ContentData_Guid, @ContentData, CASE WHEN @Version IS NULL THEN 1 ELSE @Version END, @VersionComment, @ImportDate);

			UPDATE	Content_Item
			SET		ContentData_Guid = @ContentData_Guid
			WHERE	ContentItem_Guid = @UniqueId
		END
		
		IF @UserGuid IS NOT NULL
		BEGIN
			UPDATE	ContentData_Text
			SET		Modified_Date = getUTCdate(),
					Modified_By = @UserGuid,
					ContentData_Version = CASE WHEN @Version IS NULL THEN ContentData_Version + 1 ELSE @Version END,
					VersionComment = @VersionComment,
					Import_Date = @ImportDate
			WHERE	ContentData_Guid = @ContentData_Guid;
		END
	END

GO
ALTER PROCEDURE [dbo].[spLibrary_AddNewLibraryVersion]
	@ContentData_Guid uniqueidentifier,
	@IsBinary bit,
	@ContentItem_Guid varchar(40)
AS
	BEGIN TRAN

	If (@IsBinary = 1)
	BEGIN
		INSERT INTO ContentData_Binary_Version 
			(ContentData_Version, 
			ContentData_Guid, 
			ContentData,
			FileType,
			Modified_Date, 
			Modified_By,
			Approved,
			VersionComment,
			Import_Date)
		SELECT ContentData_Binary.ContentData_Version,
			ContentData_Binary.ContentData_Guid,
			ContentData_Binary.ContentData,
			ContentData_Binary.FileType,
			ContentData_Binary.Modified_Date,
			ContentData_Binary.Modified_By,
			CASE Content_Item.Approved WHEN 0 THEN 1 ELSE Content_Item.Approved END AS Approved,
			ContentData_Binary.VersionComment,
			ContentData_Binary.Import_Date
		FROM ContentData_Binary	
			INNER JOIN Content_Item ON ContentData_Binary.ContentData_Guid = Content_Item.ContentData_Guid
		WHERE ContentData_Binary.ContentData_Guid = @ContentData_Guid;
	END
	ELSE
	BEGIN
		INSERT INTO ContentData_Text_Version 
			(ContentData_Version, 
			ContentData_Guid, 
			ContentData,
			Modified_Date, 
			Modified_By,
			Approved,
			VersionComment,
			Import_Date)
		SELECT ContentData_Text.ContentData_Version,
			ContentData_Text.ContentData_Guid,
			ContentData_Text.ContentData,
			ContentData_Text.Modified_Date,
			ContentData_Text.Modified_By,
			CASE Content_Item.Approved WHEN 0 THEN 1 ELSE Content_Item.Approved END AS Approved,
			ContentData_Text.VersionComment,
			ContentData_Text.Import_Date
		FROM ContentData_Text
			INNER JOIN Content_Item ON ContentData_Text.ContentData_Guid = Content_Item.ContentData_Guid
		WHERE ContentData_Text.ContentData_Guid = @ContentData_Guid;
	END
	
	IF (SELECT COUNT(*)
		FROM	Template
			INNER JOIN Template_Group ON Template_Group.Layout_Guid = Template.Template_Guid OR Template_Group.Template_Guid = Template.Template_Guid
			INNER JOIN Xtf_ContentLibrary_Dependency on Xtf_ContentLibrary_Dependency.Template_Guid = Template.Template_Guid
		WHERE	Template_Group.MatchProjectVersion = 1
			AND Xtf_ContentLibrary_Dependency.Content_Object_Guid = @ContentItem_Guid) = 0
	BEGIN
		EXEC spLibrary_ClearExcessVersions @ContentData_Guid, @IsBinary;
	END
			
	COMMIT

GO
ALTER procedure [dbo].[spLibrary_RestoreVersion]
	@ContentItemGuid uniqueidentifier,
	@VersionNumber int,
	@UserGuid uniqueidentifier,
	@RestoreVersionComment nvarchar(max)
AS
	SET NOCOUNT ON
	
	DECLARE @ContentData_Guid uniqueidentifier
	DECLARE @IsBinary bit
	
	SELECT	@ContentData_Guid = ContentData_Guid, 
			@IsBinary = CASE WHEN ContentType_Id = 2 THEN 0 ELSE 1 END
	FROM	Content_Item
	WHERE	ContentItem_Guid = @ContentItemGuid;
		
	BEGIN TRAN	
	
	EXEC spLibrary_AddNewLibraryVersion @ContentData_Guid, @IsBinary, @ContentItemGuid;
	
	IF (@IsBinary = 1)
	BEGIN
		UPDATE	ContentData_Binary
		SET		ContentData = ContentData_Binary_Version.ContentData, 
				FileType = ContentData_Binary_Version.FileType,
				ContentData_Version = ContentData_Binary.ContentData_Version + 1, 
				Modified_Date = GetUTCdate(),
				Modified_By = @UserGuid,
				VersionComment = @RestoreVersionComment,
				Import_Date = ContentData_Binary_Version.Import_Date
		FROM	ContentData_Binary, 
				ContentData_Binary_Version
		WHERE	ContentData_Binary.ContentData_Guid = @ContentData_Guid
				AND ContentData_Binary_Version.ContentData_Guid = @ContentData_Guid 
				AND	ContentData_Binary_Version.ContentData_Version = @VersionNumber;
	END
	ELSE
	BEGIN
		UPDATE	ContentData_Text
		SET		ContentData = ContentData_Text_Version.ContentData, 
				ContentData_Version = ContentData_Text.ContentData_Version + 1, 
				Modified_Date = GetUTCdate(),
				Modified_By = @UserGuid,
				VersionComment = @RestoreVersionComment,
				Import_Date = ContentData_Text_Version.Import_Date
		FROM	ContentData_Text, 
				ContentData_Text_Version
		WHERE	ContentData_Text.ContentData_Guid = @ContentData_Guid
				AND ContentData_Text_Version.ContentData_Guid = @ContentData_Guid 
				AND	ContentData_Text_Version.ContentData_Version = @VersionNumber;
	END
		
	IF (SELECT COUNT(*)
		FROM	Template
			INNER JOIN Template_Group ON Template_Group.Layout_Guid = Template.Template_Guid OR Template_Group.Template_Guid = Template.Template_Guid
			INNER JOIN Xtf_ContentLibrary_Dependency on Xtf_ContentLibrary_Dependency.Template_Guid = Template.Template_Guid
		WHERE	Template_Group.MatchProjectVersion = 1
			AND Xtf_ContentLibrary_Dependency.Content_Object_Guid = @ContentItemGuid) = 0
	BEGIN
		EXEC spLibrary_ClearExcessVersions @ContentData_Guid, @IsBinary;
	END
	
	UPDATE	Content_Item
	SET		IsIndexed = 0
	WHERE	ContentItem_Guid = @ContentItemGuid;
	
	DELETE	Content_Item_Placeholder
	WHERE	ContentItemGuid = @ContentItemGuid;
		
	COMMIT

GO
CREATE PROCEDURE dbo.spContent_GetLatestVersionDetails (
	@UniqueId uniqueidentifier
)
AS
	DECLARE @ContentData_Guid uniqueidentifier
	DECLARE @MaxVersion int

	SET @ContentData_Guid = (SELECT ContentData_Guid FROM Content_Item WHERE Content_Item.ContentItem_Guid = @UniqueId)

	IF (@ContentData_Guid IS NULL)
	BEGIN
		SELECT NULL as ContentData_Version, NULL as Modified_Date, NULL as Import_Date
	END
	ELSE
	BEGIN
		SELECT	@MaxVersion = MAX(ContentData_Version)
		FROM	(SELECT ContentData_Version
				FROM	ContentData_Binary_Version
				WHERE	ContentData_Guid = @ContentData_Guid
				UNION
				SELECT	ContentData_Version
				FROM	ContentData_Binary
				WHERE	ContentData_Guid = @ContentData_Guid
				UNION
				SELECT  ContentData_Version
				FROM	ContentData_Text_Version
				WHERE	ContentData_Guid = @ContentData_Guid
				UNION
				SELECT	ContentData_Version
				FROM	ContentData_Text
				WHERE	ContentData_Guid = @ContentData_Guid) Versions

		SELECT	ContentData_Version, Modified_Date, Import_Date
		FROM	ContentData_Binary_Version
		WHERE	ContentData_Guid = @ContentData_Guid AND ContentData_Version = @MaxVersion
		UNION
		SELECT	ContentData_Version, Modified_Date, Import_Date
		FROM	ContentData_Binary
		WHERE	ContentData_Guid = @ContentData_Guid AND ContentData_Version = @MaxVersion
		UNION
		SELECT  ContentData_Version, Modified_Date, Import_Date
		FROM	ContentData_Text_Version
		WHERE	ContentData_Guid = @ContentData_Guid AND ContentData_Version = @MaxVersion
		UNION
		SELECT	ContentData_Version, Modified_Date, Import_Date
		FROM	ContentData_Text
		WHERE	ContentData_Guid = @ContentData_Guid AND ContentData_Version = @MaxVersion
	END
GO
ALTER procedure [dbo].[spLibrary_GetContentVersions]
	@ContentItemGuid uniqueidentifier
as
	DECLARE @ContentData_Guid uniqueidentifier
	DECLARE @Approved Int
	DECLARE @ExpiryDate datetime
	
	UPDATE Content_Item
	SET Approved = 1
	WHERE ExpiryDate < GETDATE()
		And ContentItem_Guid = @ContentItemGuid;

	SELECT	@ContentData_Guid = ContentData_Guid, @Approved = Approved, @ExpiryDate = ExpiryDate
	FROM	Content_Item
	WHERE	ContentItem_Guid = @ContentItemGuid;

	SELECT	ContentData_Version, Modified_Date, Versions.Modified_By, Intelledox_User.Username,
			Approved, ExpiryDate, Versions.VersionComment, Versions.Import_Date
	FROM	(SELECT	ContentData_Guid, 
				Modified_Date, 
				Modified_By, 
				ContentData_Version, 
				@Approved as Approved, 
				@ExpiryDate AS ExpiryDate,
				VersionComment,
				Import_Date
			FROM	ContentData_Binary
			UNION
			SELECT	ContentData_Guid, 
				Modified_Date, 
				Modified_By, 
				ContentData_Version, 
				Approved, 
				NULL AS ExpiryDate,
				VersionComment,
				Import_Date
			FROM	ContentData_Binary_Version
			UNION
			SELECT	ContentData_Guid, 
				Modified_Date, 
				Modified_By, 
				ContentData_Version, 
				@Approved as Approved, 
				@ExpiryDate AS ExpiryDate,
				VersionComment,
				Import_Date
			FROM	ContentData_Text
			UNION
			SELECT	ContentData_Guid, 
				Modified_Date, 
				Modified_By, 
				ContentData_Version, 
				Approved, 
				NULL AS ExpiryDate,
				VersionComment,
				Import_Date
			FROM	ContentData_Text_Version) Versions
			LEFT JOIN Intelledox_User ON Intelledox_User.User_Guid = Versions.Modified_By
	WHERE	ContentData_Guid = @ContentData_Guid
	ORDER BY ContentData_Version DESC;
GO
EXEC SP_RENAME 'dbo.admin_group', 'zzadmin_group'
GO
ALTER TABLE AssetStorage 
	ADD EncryptedData [varbinary](max) NULL,
	    AssetLength int NOT NULL DEFAULT(0)
GO

UPDATE AssetStorage
SET AssetLength = DATALENGTH([Data])
WHERE AssetLength = 0
GO

ALTER TABLE AssetStorage ALTER COLUMN [Data] [varbinary](max) NULL
GO

ALTER PROCEDURE [dbo].[spAssetStorage_Get]
	@Id uniqueidentifier
AS
	SELECT	AssetLength, Data, EncryptedData, BusinessUnitGuid
	FROM	AssetStorage
	WHERE	Id = @Id;
GO

ALTER PROCEDURE [dbo].[spAssetStorage_Store]
	@BusinessUnitGuid uniqueidentifier,
	@Id uniqueidentifier,
	@DateCreatedUtc datetime,
	@RunID uniqueidentifier,
	@Data varbinary(max),
	@EncryptedData varbinary(max),
	@AssetLength int
AS
	IF EXISTS(SELECT 1 FROM AssetStorage WHERE Id = @Id )
	BEGIN
		--For switching between encryption settings
		UPDATE AssetStorage
		SET [Data] = @Data,
			EncryptedData = @EncryptedData,
			AssetLength = @AssetLength
		WHERE Id = @Id
	END
	ELSE
	BEGIN
		INSERT AssetStorage(BusinessUnitGuid, Id, Data, DateCreatedUtc, EncryptedData, AssetLength)
		VALUES (@BusinessUnitGuid, @Id, @Data, @DateCreatedUtc, @EncryptedData, @AssetLength);

		INSERT AssetRunID(ID, AssetID, RunID)
		VALUES (NEWID(), @Id, @RunID)
	END
GO
CREATE PROCEDURE [dbo].[spAssetStorage_FullList]
	@BusinessUnitGuid uniqueIdentifier,
	@EncryptedOnly bit
AS
BEGIN
	IF (@EncryptedOnly = 1)
	BEGIN
		SELECT AssetStorage.Id, AssetRunID.RunID
		FROM AssetStorage
		INNER JOIN AssetRunID ON AssetStorage.Id = AssetRunID.AssetID
		WHERE BusinessUnitGuid = @BusinessUnitGuid AND AssetStorage.EncryptedData IS NOT NULL
	END
	ELSE
	BEGIN
		SELECT AssetStorage.Id, AssetRunID.RunID
		FROM AssetStorage
		INNER JOIN AssetRunID ON AssetStorage.Id = AssetRunID.AssetID
		WHERE BusinessUnitGuid = @BusinessUnitGuid AND AssetStorage.[Data] IS NOT NULL
	END
END
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
	DECLARE @RunId uniqueidentifier;

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
	-- Expired Assets
	CREATE TABLE #ExpiredAssetItems 
	( 
		Id uniqueidentifier NOT NULL,
		RunId uniqueidentifier NOT NULL
	)

	-- Join data that has an AssetRunId entry only
	INSERT #ExpiredAssetItems (Id, RunId)
	SELECT AssetStorage.Id, AssetRunID.RunID
	FROM AssetStorage WITH (READUNCOMMITTED)
	INNER JOIN AssetRunID assetRunId on assetRunId.AssetID = AssetStorage.Id
	WHERE DateCreatedUtc < @GenerationCleanupDate

	IF @@ROWCOUNT <> 0 
	BEGIN 
		DECLARE ExpiredItemCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
		FOR SELECT Id, RunId FROM #ExpiredAssetItems 

		OPEN ExpiredItemCursor;
		FETCH NEXT FROM ExpiredItemCursor INTO @GuidId, @RunId;

		WHILE @@FETCH_STATUS = 0 
			BEGIN
				BEGIN TRANSACTION AL;

				DELETE assetRunId FROM AssetRunID assetRunId
				INNER JOIN AssetStorage asset on assetRunId.AssetID = asset.Id
				WHERE asset.Id = @GuidId AND assetRunID.RunID = @RunId AND @RunId NOT IN 
					(SELECT tl.RunID FROM Template_Log tl WHERE tl.RunID = @RunId
					 UNION
					 SELECT als.RunID FROM ActionListState als WHERE als.RunID = @RunId
					 UNION
					 SELECT af.RunID FROM Answer_File af WHERE af.RunID = @RunId)

				DELETE asset FROM AssetStorage asset
				WHERE asset.Id = @GuidId AND asset.ID NOT IN (SELECT AssetRunID.AssetID FROM AssetRunID)
			
				COMMIT TRANSACTION AL;

				FETCH NEXT FROM ExpiredItemCursor INTO @GuidId, @RunId;
			END

		CLOSE ExpiredItemCursor;
		DEALLOCATE ExpiredItemCursor;

	END 
	
	DROP TABLE #ExpiredAssetItems;

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
	
	-- ==================================================
	-- Pending transitions
	IF EXISTS(SELECT * FROM PendingWorkflowTransition)
	BEGIN
	
		DECLARE @ActionListStateId uniqueidentifier;
		CREATE TABLE #ExpiredActionListStates
		(
			ActionListStateId uniqueidentifier NOT NULL PRIMARY KEY
		)
		
		INSERT #ExpiredActionListStates (ActionListStateId)
		SELECT DISTINCT ActionListStateId
		FROM ActionListState WITH (READUNCOMMITTED)
		WHERE ActionListState.IsComplete = 0;
		
		IF @@ROWCOUNT <> 0 
		BEGIN 
			DECLARE ActionListStateCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
			FOR SELECT ActionListStateId FROM #ExpiredActionListStates 

			OPEN ActionListStateCursor;
			FETCH NEXT FROM ActionListStateCursor INTO @ActionListStateId;

			WHILE @@FETCH_STATUS = 0 
				BEGIN
					EXEC spWorkflow_RemovePending @ActionListStateId;
					FETCH NEXT FROM ActionListStateCursor INTO @ActionListStateId;
				END

			CLOSE ActionListStateCursor;
			DEALLOCATE ActionListStateCursor;
		END 
	
		DROP TABLE #ExpiredActionListStates;

	END

GO
