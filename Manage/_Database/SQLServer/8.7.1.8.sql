truncate table dbversion;
go
insert into dbversion(dbversion) values ('8.7.1.8');
go
ALTER PROCEDURE [dbo].[spProjectGroup_UpdateFeatureFlags]
	@ProjectGroupGuid uniqueidentifier = null,
	@ProjectGuid uniqueidentifier = null
AS
	DECLARE @ProjectGroupsAffected TABLE 
	(
		Template_Group_Guid uniqueidentifier,
		Content_Guid uniqueidentifier,
		Layout_Guid uniqueidentifier
	)

	IF (@ProjectGuid is NULL)
	BEGIN
		-- Update a single group
		INSERT INTO @ProjectGroupsAffected(Template_Group_Guid, Content_Guid, Layout_Guid)
		SELECT @ProjectGroupGuid, Template_Guid, Layout_Guid
		FROM	Template_Group
		WHERE	Template_Group_Guid = @ProjectGroupGuid;
	END
	ELSE
	BEGIN
		-- Update groups using a project
		WITH ParentFragments (Template_Guid)
		AS
		(
			-- Anchor member definition
			SELECT	t.Template_Guid
			FROM	Xtf_Fragment_Dependency t
			WHERE	t.Fragment_Guid = @ProjectGuid
			UNION ALL
			-- Recursive member definition
			SELECT t.Template_Guid
			FROM Xtf_Fragment_Dependency t
				INNER JOIN ParentFragments AS p ON t.Fragment_Guid = p.Template_Guid
		)
		INSERT INTO @ProjectGroupsAffected(Template_Group_Guid, Content_Guid, Layout_Guid)
		SELECT DISTINCT Template_Group.Template_Group_Guid, Template_Group.Template_Guid as Content_Guid, Template_Group.Layout_Guid
		FROM ParentFragments
			INNER JOIN Template_Group ON ParentFragments.Template_Guid = Template_Group.Template_Guid
				OR ParentFragments.Template_Guid = Template_Group.Layout_Guid

		--Select parent content project guid
		INSERT INTO @ProjectGroupsAffected(Template_Group_Guid, Content_Guid, Layout_Guid)
		SELECT Template_Group_Guid, Template_Guid, Layout_Guid
		FROM	Template_Group
		WHERE	(Template_Guid = @ProjectGuid OR Layout_Guid = @ProjectGuid) AND
				Template_Group_Guid NOT IN (SELECT Template_Group_Guid FROM @ProjectGroupsAffected);

	END

	DECLARE @FeatureFlag int;
	DECLARE @Content_Guid uniqueidentifier
	DECLARE @Layout_Guid uniqueidentifier
	DECLARE @Project_Version nvarchar(10)
	DECLARE PgCursor CURSOR
		FOR	SELECT	Template_Group_Guid, Content_Guid, Layout_Guid
			FROM	@ProjectGroupsAffected;

	OPEN PgCursor;
	FETCH NEXT FROM PgCursor INTO @ProjectGroupGuid, @Content_Guid, @Layout_Guid;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		-- Content
		SET @FeatureFlag = (SELECT	Template.FeatureFlags
					FROM	Template_Group
							INNER JOIN Template ON Template_Group.Template_Guid = Template.Template_Guid 
									AND (Template_Group.Template_Version IS NULL
										OR Template_Group.Template_Version = Template.Template_Version)
					WHERE	Template_Group.Template_Group_Guid = @ProjectGroupGuid
					UNION ALL
					SELECT	Template_Version.FeatureFlags
					FROM	Template_Group
							INNER JOIN Template_Version ON (Template_Group.Template_Guid = Template_Version.Template_Guid 
									AND Template_Group.Template_Version = Template_Version.Template_Version)
					WHERE	Template_Group.Template_Group_Guid = @ProjectGroupGuid)

		SET @Project_Version = (SELECT	Template.Template_Version
					FROM	Template_Group
							INNER JOIN Template ON Template_Group.Template_Guid = Template.Template_Guid 
									AND (Template_Group.Template_Version IS NULL
										OR Template_Group.Template_Version = Template.Template_Version)
					WHERE	Template_Group.Template_Group_Guid = @ProjectGroupGuid
					UNION ALL
					SELECT	Template_Version.Template_Version
					FROM	Template_Group
							INNER JOIN Template_Version ON (Template_Group.Template_Guid = Template_Version.Template_Guid 
									AND Template_Group.Template_Version = Template_Version.Template_Version)
					WHERE	Template_Group.Template_Group_Guid = @ProjectGroupGuid)

		-- Content Project Fragments
		DECLARE FragCursor CURSOR
			FOR	WITH ChildFragments (Template_Guid)
				AS
				(
					-- Anchor member definition
					SELECT	t.Fragment_Guid
					FROM	Xtf_Fragment_Dependency t
					WHERE	t.Template_Guid = @Content_Guid AND
							t.Template_Version = @Project_Version
					UNION ALL
					-- Recursive member definition
					SELECT t.Fragment_Guid
					FROM Xtf_Fragment_Dependency t
						INNER JOIN ChildFragments AS p ON t.Template_Guid = p.Template_Guid
						INNER JOIN Template ON t.Template_Version = Template.Template_Version AND t.Template_Guid = Template.Template_Guid
				)
				SELECT Template_Guid
				FROM ChildFragments;

		OPEN FragCursor;
		FETCH NEXT FROM FragCursor INTO @ProjectGuid;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @FeatureFlag = @FeatureFlag | ISNULL((SELECT FeatureFlags
				FROM Template
				WHERE Template_Guid = @ProjectGuid), 0);

			FETCH NEXT FROM FragCursor INTO @ProjectGuid;
		END
		
		CLOSE FragCursor;
		DEALLOCATE FragCursor;

		-- Layout
		IF @Layout_Guid IS NOT NULL
		BEGIN
			SET @FeatureFlag = @FeatureFlag | ISNULL((SELECT Template.FeatureFlags
					FROM	Template_Group
							INNER JOIN Template ON Template_Group.Layout_Guid = Template.Template_Guid
									AND (Template_Group.Layout_Version IS NULL
										OR Template_Group.Layout_Version = Template.Template_Version)
					WHERE	Template_Group.Template_Group_Guid = @ProjectGroupGuid
					UNION ALL
					SELECT	Template_Version.FeatureFlags
					FROM	Template_Group
							INNER JOIN Template_Version ON Template_Group.Layout_Guid = Template_Version.Template_Guid
									AND Template_Group.Layout_Version = Template_Version.Template_Version
					WHERE	Template_Group.Template_Group_Guid = @ProjectGroupGuid), 0)

			SET @Project_Version =(SELECT Template.Template_Version
					FROM	Template_Group
							INNER JOIN Template ON Template_Group.Layout_Guid = Template.Template_Guid
									AND (Template_Group.Layout_Version IS NULL
										OR Template_Group.Layout_Version = Template.Template_Version)
					WHERE	Template_Group.Template_Group_Guid = @ProjectGroupGuid
					UNION ALL
					SELECT	Template_Version.Template_Version
					FROM	Template_Group
							INNER JOIN Template_Version ON Template_Group.Layout_Guid = Template_Version.Template_Guid
									AND Template_Group.Layout_Version = Template_Version.Template_Version
					WHERE	Template_Group.Template_Group_Guid = @ProjectGroupGuid)

			-- Layout Project fragments
			DECLARE LayoutFragCursor CURSOR
				FOR	WITH ChildFragments (Template_Guid)
					AS
					(
						-- Anchor member definition
						SELECT	t.Fragment_Guid
						FROM	Xtf_Fragment_Dependency t
						WHERE	t.Template_Guid = @Layout_Guid AND
							    t.Template_Version = @Project_Version
						UNION ALL
						-- Recursive member definition
						SELECT t.Fragment_Guid
						FROM Xtf_Fragment_Dependency t
							INNER JOIN ChildFragments AS p ON t.Template_Guid = p.Template_Guid
							INNER JOIN Template ON t.Template_Version = Template.Template_Version AND t.Template_Guid = Template.Template_Guid
					)
					SELECT Template_Guid
					FROM ChildFragments;

			OPEN LayoutFragCursor;
			FETCH NEXT FROM LayoutFragCursor INTO @ProjectGuid;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				SET @FeatureFlag = @FeatureFlag | ISNULL((SELECT FeatureFlags
					FROM Template
					WHERE Template_Guid = @ProjectGuid), 0);

				FETCH NEXT FROM LayoutFragCursor INTO @ProjectGuid;
			END
		
			CLOSE LayoutFragCursor;
			DEALLOCATE LayoutFragCursor;
		END

		UPDATE	Template_Group
		SET		Template_Group.FeatureFlags = @FeatureFlag
		WHERE	Template_Group.Template_Group_Guid = @ProjectGroupGuid;
		
		FETCH NEXT FROM PgCursor INTO @ProjectGroupGuid, @Content_Guid, @Layout_Guid;
	END

	CLOSE PgCursor;
	DEALLOCATE PgCursor;
GO










