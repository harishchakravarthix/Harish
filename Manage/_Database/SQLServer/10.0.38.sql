truncate table dbversion;
go
insert into dbversion(dbversion) values ('10.0.38');
GO

ALTER VIEW [dbo].[vwUserDetails]
AS
SELECT  u.User_ID, u.Username, u.pwdhash, u.WinNT_User, u.IsTemporaryUser AS TemporaryUser, u.Business_Unit_GUID, u.User_Guid, u.SelectedTheme, u.ChangePassword, 
        u.Disabled, u.Address_ID, u.Timezone, u.Culture, u.Language, ab.Addresstype_ID, ab.Address_Reference, 
        ab.Prefix, ab.First_Name, ab.Last_Name, ab.Full_Name, ab.Salutation_Name, ab.Title, ab.Organisation_Name, ab.Phone_Number, ab.Fax_Number, 
        ab.Email_Address, ab.Street_Address_1, ab.Street_Address_2, ab.Street_Address_Suburb, ab.Street_Address_State, ab.Street_Address_Postcode, 
        ab.Street_Address_Country, ab.Postal_Address_1, ab.Postal_Address_2, ab.Postal_Address_Suburb, ab.Postal_Address_State, 
        ab.Postal_Address_Postcode, ab.Postal_Address_Country
FROM    dbo.Intelledox_User AS u INNER JOIN
        dbo.Address_Book AS ab ON u.Address_ID = ab.Address_ID
GO
