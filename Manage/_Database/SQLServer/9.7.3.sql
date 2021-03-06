truncate table dbversion;
go
insert into dbversion(dbversion) values ('9.7.3');
go


ALTER TABLE Data_Object
ADD Cache_Warning int NOT NULL DEFAULT(0),
    Cache_Warning_Message nvarchar(256) NULL,
    Cache_Expiry int NOT NULL DEFAULT(0),
	UseAnswerFileData BIT NOT NULL DEFAULT(0)
GO

UPDATE Data_Object 
SET Cache_Warning = Cache_Duration
GO

ALTER PROCEDURE [dbo].[spDataSource_DataObjectList]
	@DataObjectGuid uniqueidentifier = null,
	@DataServiceGuid uniqueidentifier = null
AS
	IF @DataObjectGuid IS NULL
		SELECT	o.[Object_Name], o.data_object_guid, o.data_service_guid, o.Merge_Source, 
				o.Object_Type, o.Display_Name, o.Allow_Cache, o.Cache_Duration, o.Cache_Warning, 
				o.Cache_Warning_Message, o.Cache_Expiry, o.UseAnswerFileData
		FROM	data_object o
		WHERE	o.data_service_guid = @DataServiceGuid
		ORDER BY o.Display_Name;
	ELSE
		SELECT	o.[Object_Name], o.data_object_guid, o.data_service_guid, o.Merge_Source, 
				o.Object_Type, o.Display_Name, o.Allow_Cache, o.Cache_Duration, o.Cache_Warning, 
				o.Cache_Warning_Message, o.Cache_Expiry, o.UseAnswerFileData
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
	@CacheDuration int,
	@CacheWarning int,
	@CacheWarningMessage nvarchar(256),
	@CacheExpiry int,
	@UseAnswerFileData bit
AS
	IF NOT EXISTS(SELECT * FROM data_object WHERE Data_Object_Guid = @DataObjectGuid)
	BEGIN
		INSERT INTO data_object (Data_Service_Guid, [Object_Name], Merge_Source, 
				Data_Object_Guid, Object_Type, Display_Name, Allow_Cache, Cache_Duration,
				Cache_Warning, Cache_Warning_Message, Cache_Expiry, UseAnswerFileData)
		VALUES (@DataServiceGuid, @Name, @MergeSource, @DataObjectGuid,
				 @ObjectType, @DisplayName, @AllowCache, @CacheDuration,
				 @CacheWarning, @CacheWarningMessage, @CacheExpiry, @UseAnswerFileData);
	END	
	ELSE
	BEGIN		
		UPDATE	data_object
		SET		[object_name] = @Name, 
				merge_source = @MergeSource,
				Object_Type = @ObjectType,
				Display_Name = @DisplayName,
				Allow_Cache = @AllowCache,
				Cache_Duration = @CacheDuration,
				Cache_Warning = @CacheWarning,
				Cache_Warning_Message = @CacheWarningMessage,
				Cache_Expiry = @CacheExpiry,
				UseAnswerFileData = @UseAnswerFileData
		WHERE	data_object_guid = @DataObjectGuid;
	END
GO

ALTER PROCEDURE [dbo].[spGetCached_DataSourceDependencies] (
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
		Data_Object.Cache_Duration,
		Data_Object.Cache_Warning,
		Data_Object.Cache_Warning_Message,
		Data_Object.Cache_Expiry,
		Data_Object.UseAnswerFileData
	FROM [Data_Object]
	inner join Xtf_Datasource_Dependency ON Xtf_Datasource_Dependency.Data_Object_Guid = [Data_Object].Data_Object_Guid
	AND Xtf_Datasource_Dependency.Template_Guid = @ProjectGuid
	WHERE Data_Object.Allow_Cache = 1 OR Data_Object.UseAnswerFileData = 1
GO

ALTER TABLE User_Device
ADD DeviceEnvironment int NOT NULL DEFAULT(0)
GO

ALTER PROCEDURE [dbo].[spUser_RegisterDeviceToken] (
	@UserGuid uniqueidentifier,
	@DeviceToken [nvarchar](200),
	@DeviceType [int],
	@DeviceEnvironment [int]
)
AS
	IF EXISTS(SELECT * FROM User_Device WHERE DeviceToken = @DeviceToken)
	BEGIN
		UPDATE User_Device
		SET UserGuid = @UserGuid
		WHERE DeviceToken = @DeviceToken
	END
	ELSE 
	BEGIN
		IF NOT EXISTS(SELECT * FROM User_Device WHERE UserGuid = @UserGuid AND DeviceToken = @DeviceToken)
		BEGIN
			INSERT INTO User_Device (UserGuid, DeviceToken, DeviceType, DeviceEnvironment)
			VALUES (@UserGuid, @DeviceToken, @DeviceType, @DeviceEnvironment)
		END
	END

GO

ALTER VIEW dbo.vwUserAI
AS
	SELECT u.Business_Unit_GUID as BusinessUnitGuid,
			u.User_Guid as UserGuid,
			u.IsGuest,
			u.[Disabled],
			u.Username COLLATE Latin1_General_CI_AI as Username,
			ud.First_Name COLLATE Latin1_General_CI_AI as FirstName,
			ud.Last_Name COLLATE Latin1_General_CI_AI as LastName
	FROM Intelledox_User u
		LEFT JOIN Address_Book ud ON u.Address_ID = ud.Address_ID;
GO
