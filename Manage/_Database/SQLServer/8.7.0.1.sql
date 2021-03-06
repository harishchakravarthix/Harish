truncate table dbversion;
go
insert into dbversion(dbversion) values ('8.7.0.1');
go
ALTER PROCEDURE spWorkflowEscalationCleanup(
	@TaskListStateId uniqueidentifier,
	@ClearCompleteOnly bit = 1
	)
AS
BEGIN
	DECLARE @State TABLE
	(
		ActionListStateId uniqueidentifier
	)

	DECLARE @Escalation TABLE
	(
		RecurrenceId uniqueidentifier, 
		EscalationId uniqueidentifier, 
		ActionListStateId uniqueidentifier
	)

	/* Find the taskid so we can fetch all the other states */
	declare @taskID uniqueidentifier 
	set @taskID = (Select ActionListId from actionliststate where actionliststateid = @taskListStateId)

	IF (@ClearCompleteOnly = 1)
		BEGIN
			INSERT INTO @State(ActionListStateId)
			SELECT ActionListStateId 
			FROM ActionListState 
			WHERE actionListId = @taskID 
				and iscomplete=1
		END
	ELSE
		BEGIN
			INSERT INTO @State(ActionListStateId)
			SELECT ActionListStateId 
			FROM ActionListState 
			WHERE actionListId = @taskID
		END

	INSERT INTO @Escalation (RecurrenceId, EscalationId, ActionListStateId)
	SELECT we.RecurrenceId, we.EscalationId, we.ActionListStateId
	FROM Workflow_Escalation we
		JOIN @State tt ON we.ActionListStateId = tt.ActionListStateId

	DELETE rp
	FROM RecurrencePattern rp
		JOIN @Escalation esc ON rp.RecurrencePatternId = esc.RecurrenceId

	DELETE ep
	FROM EscalationProperties ep
		JOIN @Escalation esc ON ep.EscalationId = esc.Escalationid

	DELETE we
	FROM Workflow_Escalation we
		JOIN @Escalation esc ON we.EscalationId = esc.EscalationId
END
GO

ALTER TABLE [Intelledox_User]
ADD EulaAcceptanceUtc DATETIME null
GO

ALTER TABLE Business_Unit
ADD Eula NVARCHAR(MAX) null,
    EnforceEula bit not null default 0
GO

ALTER procedure [dbo].[spTenant_UpdateBusinessUnit]
	@BusinessUnitGuid uniqueidentifier,
	@Name nvarchar(200),
	@SubscriptionType int,
	@ExpiryDate datetime,
	@TenantFee money,
	@DefaultCulture nvarchar(11),
	@DefaultLanguage nvarchar(11),
	@DefaultTimezone nvarchar(50),
	@UserFee money,
	@SamlEnabled bit, 
	@SamlCertificate nvarchar(max), 
	@SamlCertificateType int, 
	@SamlCreateUsers bit, 
	@SamlIssuer nvarchar(255), 
	@SamlLoginUrl nvarchar(1500), 
	@SamlLogoutUrl nvarchar(1500),
	@SamlManageEntityId nvarchar(1500),
	@SamlProduceEntityId nvarchar(1500),
	@SamlLastLoginFail nvarchar(max),
	@TenantKey varbinary(50),
	@Eula nvarchar(max),
	@EnforceEula bit
AS
	UPDATE	Business_Unit
	SET		Name = @Name,
			SubscriptionType = @SubscriptionType,
			ExpiryDate = @ExpiryDate,
			TenantFee = @TenantFee,
			DefaultCulture = @DefaultCulture,
			DefaultLanguage = @DefaultLanguage,
			DefaultTimezone = @DefaultTimezone,
			UserFee = @UserFee,
			SamlEnabled = @SamlEnabled,
			SamlCertificate = @SamlCertificate,
			SamlCertificateType = @SamlCertificateType, 
			SamlCreateUsers = @SamlCreateUsers, 
			SamlIssuer = @SamlIssuer, 
			SamlLoginUrl = @SamlLoginUrl, 
			SamlLogoutUrl = @SamlLogoutUrl,
			SamlManageEntityId = @SamlManageEntityId,
			SamlProduceEntityId = @SamlProduceEntityId,
			SamlLastLoginFail = @SamlLastLoginFail,
			TenantKey = @TenantKey,
			Eula = @Eula,
			EnforceEula = @EnforceEula
	WHERE	Business_Unit_Guid = @BusinessUnitGuid;
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
	@IsGuest bit = 0,
	@ErrorCode int = 0 output
as
	if @UserID = 0 OR @UserID IS NULL
	begin
		INSERT INTO Intelledox_User(Username, PwdHash, WinNT_User, Business_Unit_GUID, User_Guid, SelectedTheme, 
				ChangePassword, PwdSalt, PwdFormat, [Disabled], Address_ID, Timezone, Culture, Language, IsGuest, Invalid_Logon_Attempts, Password_Set_Utc, EulaAcceptanceUtc)
		VALUES (@Username, @Password, @WinNT_User, @BusinessUnitGUID, @User_Guid, @SelectedTheme, 
				@ChangePassword, @PasswordSalt, @PasswordFormat, @Disabled, @Address_Id, @Timezone, @Culture, @Language, @IsGuest, @InvalidLogonAttempts, @PasswordSetUtc, @EulaAcceptedUtc);
		
		select @NewID = @@identity;

		INSERT INTO User_Group_Subscription(UserGuid, GroupGuid, IsDefaultGroup)
		SELECT	@User_Guid, User_Group.Group_Guid, 0
		FROM	User_Group
		WHERE	User_Group.AutoAssignment = 1
				AND Business_Unit_Guid = @BusinessUnitGUID;
	end
	else
	begin
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
			EulaAcceptanceUtc = @EulaAcceptedUtc
		WHERE [User_ID] = @UserID;
	end

	set @ErrorCode = @@error;

GO

CREATE PROCEDURE [dbo].[spTenant_ResetEulaAcceptance]
	@BusinessUnitGuid uniqueidentifier
AS
	UPDATE	Intelledox_User
	SET		EulaAcceptanceUtc = NULL
	WHERE	Business_Unit_GUID = @BusinessUnitGuid
			AND EulaAcceptanceUtc is not null
GO

CREATE PROC dbo.spProject_GetFragmentDependencies
	@ProjectGuid uniqueidentifier,
	@VersionNumber nvarchar(10) = '0'
AS
	IF (@VersionNumber = '0')
	BEGIN
		SET @VersionNumber = (SELECT Template_Version FROM Template WHERE Template_Guid = @ProjectGuid)
	END

	SELECT	Fragment_Guid
	FROM	Xtf_Fragment_Dependency
	WHERE	Template_Guid = @ProjectGuid
			AND Template_Version  = @VersionNumber;
GO
