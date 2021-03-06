truncate table dbversion;
go
insert into dbversion(dbversion) values ('9.5.0');
go

ALTER TABLE [dbo].[Global_Options] ALTER COLUMN OptionValue nvarchar(max)
GO

ALTER procedure [dbo].[spOptions_UpdateOptionValue]
	@BusinessUnitGuid uniqueidentifier,
	@Code nvarchar(255),
	@Value nvarchar(max)
as
	UPDATE	Global_Options
	SET		optionvalue = @Value
	WHERE	optioncode = @Code
			AND (BusinessUnitGuid = '00000000-0000-0000-0000-000000000000' OR BusinessUnitGuid = @BusinessUnitGuid);

GO

INSERT INTO Global_Options (BusinessUnitGuid,OptionCode,OptionDescription,OptionValue)
SELECT bu.Business_Unit_GUID,'APPLE_PUSH_CERT','Certificate for Apple device push notifications', null
FROM Business_Unit bu
GO

INSERT INTO Global_Options (BusinessUnitGuid,OptionCode,OptionDescription,OptionValue)
SELECT bu.Business_Unit_GUID,'APPLE_PUSH_CERT_PASSWORD','Password for Apple device push notifications certificate', null
FROM Business_Unit bu
GO

INSERT INTO Global_Options (BusinessUnitGuid,OptionCode,OptionDescription,OptionValue)
SELECT bu.Business_Unit_GUID,'ANDROID_PUSH_API_KEY','API Key for Android device push notifications', null
FROM Business_Unit bu
GO

CREATE TABLE [dbo].[User_Device] (
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[UserGuid] [uniqueidentifier] NOT NULL,
    [DeviceToken] [nvarchar](200) NULL,
	[DeviceType] [int]  NOT NULL
	CONSTRAINT [User_Device_Android_pk] PRIMARY KEY CLUSTERED 
	(
		ID
	)
)
GO

CREATE PROCEDURE [dbo].[spUser_RegisterDeviceToken] (
	@UserGuid uniqueidentifier,
	@DeviceToken [nvarchar](200),
	@DeviceType [int]
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
			INSERT INTO User_Device (UserGuid, DeviceToken, DeviceType)
			VALUES (@UserGuid, @DeviceToken, @DeviceType)
		END
	END

GO

CREATE PROCEDURE [dbo].[spUser_RemoveDeviceToken] (
	@UserGuid uniqueidentifier,
	@OldDeviceToken [nvarchar](200)
)
AS
	DELETE FROM [User_Device]
	WHERE [UserGuid] = @UserGuid AND [DeviceToken] = @OldDeviceToken
GO

CREATE PROCEDURE [dbo].[spUser_GetDeviceTokens] (
	@UserGuid uniqueidentifier,
	@DeviceType int
)
AS
	SELECT * 
	FROM [User_Device]
	WHERE [UserGuid] = @UserGuid AND [DeviceType] = @DeviceType
GO


/****** Object:  StoredProcedure [dbo].[spTenant_RemoveLogo]    Script Date: 30/03/2016 2:05:17 PM ******/
DROP PROCEDURE [dbo].[spTenant_RemoveLogo]
GO

/****** Object:  StoredProcedure [dbo].[spTenant_UpdateTenant]    Script Date: 30/03/2016 2:04:36 PM ******/
ALTER PROCEDURE [dbo].[spTenant_UpdateTenant]
	@BusinessUnitID uniqueidentifier,
	@TenantName nvarchar(200) = '',
	@TenantType int	

AS

	UPDATE	Business_Unit
	SET		NAME = @TenantName,
			TenantType = @TenantType
	WHERE	Business_Unit_GUID = @BusinessUnitID;

GO

-- add new skinning option
INSERT INTO Global_Options (BusinessUnitGuid,OptionCode,OptionDescription,OptionValue)
SELECT bu.Business_Unit_GUID,'SKIN_XML','Tenant skin xml', null
FROM Business_Unit bu
GO

-- move existing tenant logos into global_options
SET ARITHABORT ON
UPDATE [Global_Options] SET [BusinessUnitGuid] = b.business_unit_guid,[OptionValue] = b.value
FROM [Global_Options] g
INNER JOIN (
SELECT business_unit_guid, (
SELECT  ( SELECT convert(varbinary(max), tenantlogo, 1) as Image from 
[Business_Unit]
FOR
XML PATH('Logo'), BINARY BASE64,
TYPE
)
FOR XML PATH(''),
ROOT('Skin')
) as Value
from  [Business_Unit]) b 
ON b.business_unit_guid = g.BusinessUnitGuid and g.OptionCode = 'SKIN_XML'
GO

-- remove unneeded column
ALTER TABLE [Business_Unit] DROP COLUMN tenantlogo --
GO


INSERT INTO Global_Options (BusinessUnitGuid, OptionCode, OptionDescription, OptionValue)
VALUES ('00000000-0000-0000-0000-000000000000', 'TRANSACTION_EMAIL', 'Email to send monthly transaction information to', '')
GO

DELETE FROM Global_Options
WHERE OptionCode = 'WORD_XML' Or 
OptionCode = 'ADMIN_AUTH_MODE' or
OptionCode = 'HAS_LEGACY_PROVIDERS' or
OptionCode = 'LOG_WIZARD_PAGE' or
OptionCode = 'LOG_TEMPLATE' or
OptionCode = 'USER_AUTH_MODE'
GO
