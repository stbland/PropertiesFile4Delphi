unit PropertiesFile4D.Mapping;

interface

{$INCLUDE PropertiesFile4D.inc}

uses
  {$IFDEF USE_SYSTEM_NAMESPACE}
  System.Classes,
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  {$ELSE USE_SYSTEM_NAMESPACE}
  Classes,
  SysUtils,
  Rtti,
  TypInfo,
  Generics.Collections,
  {$ENDIF USE_SYSTEM_NAMESPACE}
  PropertiesFile4D;

type

  PropertiesFileAttribute = class(TCustomAttribute)
  strict private
    FFileName: string;
    FPrefix: string;
  public
    constructor Create(const pFileName: string; const pPrefix: string = '');

    property FileName: string read FFileName;
    property Prefix: string read FPrefix;
  end;

  PropertyItemAttribute = class(TCustomAttribute)
  strict private
    FName: string;
  public
    constructor Create(const pName: string);

    property Name: string read FName;
  end;

  NotNullAttribute = class(TCustomAttribute)

  end;

  IgnoreAttribute = class(TCustomAttribute)

  end;

  ReadOnlyAttribute = class(TCustomAttribute)

  end;

  TMappedPropertiesFile = class
  strict private
    [Ignore]
    FPropFile: IPropertiesFile;
    [Ignore]
    FRttiCtx: TRttiContext;
    [Ignore]
    FRttiType: TRttiType;
    [Ignore]
    FFieldList: TDictionary<string, TRttiField>;
    [Ignore]
    FFileName: string;
    [Ignore]
    FPrefix: string;
    procedure Load();
    procedure Unload();
    procedure SetFileNameAndPrefix();
    function IsReadOnly(): Boolean;
    function IsIgnoreField(const pField: TRttiField): Boolean;
    function IsNotNullField(const pField: TRttiField): Boolean;
    function GetFieldName(const pField: TRttiField): string;
  public
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;

    procedure Reload();
    procedure Save();
  end;

implementation

function isEmpty(const pString: string): Boolean;
begin
  {$IFDEF USE_STRING_CLASS}
  Result := pString.isEmpty;
  {$ELSE USE_STRING_CLASS}
  Result := pString = '';
  {$ENDIF USE_STRING_CLASS}
end;

function isEquals(const pString1, pString2: string): Boolean;
begin
  {$IFDEF USE_STRING_CLASS}
  Result := pString1.Equals(pString2);
  {$ELSE USE_STRING_CLASS}
  Result := pString1 = pString2;
  {$ENDIF USE_STRING_CLASS}
end;

{ ConfigurationAttribute }

constructor PropertiesFileAttribute.Create(const pFileName: string; const pPrefix: string = '');
begin
  FFileName := pFileName;
  FPrefix := pPrefix;
end;

{ NameAttribute }

constructor PropertyItemAttribute.Create(const pName: string);
begin
  FName := pName;
end;

{ TMappedPropertiesFile }

procedure TMappedPropertiesFile.AfterConstruction;
begin
  inherited AfterConstruction;
  FPropFile := TPropertiesFileFactory.Build();
  FRttiCtx := TRttiContext.Create();
  FRttiType := FRttiCtx.GetType(Self.ClassType);
  FFieldList := TDictionary<string, TRttiField>.Create();
  FFileName := EmptyStr;
  FPrefix := EmptyStr;
  Load();
end;

procedure TMappedPropertiesFile.BeforeDestruction;
begin
  Unload();
  FreeAndNil(FFieldList);
  FRttiCtx.Free;
  inherited BeforeDestruction;
end;

function TMappedPropertiesFile.GetFieldName(const pField: TRttiField): string;
var
  vAttr: TCustomAttribute;
begin
  Result := EmptyStr;
  for vAttr in pField.GetAttributes() do
    if (vAttr is PropertyItemAttribute) then
    begin
      if not isEmpty(PropertyItemAttribute(vAttr).Name) then
        if isEmpty(FPrefix) then
          Result := PropertyItemAttribute(vAttr).Name
        else
          Result := FPrefix + '.' + PropertyItemAttribute(vAttr).Name;
      Break;
    end;
  if isEmpty(Result) then
    if isEmpty(FPrefix) then
      Result := pField.Name
    else
      Result := FPrefix + '.' + pField.Name;
end;

function TMappedPropertiesFile.IsIgnoreField(const pField: TRttiField): Boolean;
var
  vAttr: TCustomAttribute;
begin
  Result := False;
  for vAttr in pField.GetAttributes() do
    if (vAttr is IgnoreAttribute) then
      Exit(True);
end;

function TMappedPropertiesFile.IsNotNullField(const pField: TRttiField): Boolean;
var
  vAttr: TCustomAttribute;
begin
  Result := False;
  for vAttr in pField.GetAttributes() do
    if (vAttr is NotNullAttribute) then
      Exit(True);
end;

function TMappedPropertiesFile.IsReadOnly: Boolean;
var
  vAttr: TCustomAttribute;
begin
  Result := False;
  for vAttr in FRttiType.GetAttributes() do
    if vAttr is ReadOnlyAttribute then
      Exit(True);
end;

procedure TMappedPropertiesFile.Load;
var
  vField: TRttiField;
  vFieldName: string;
  vEnumValue: TValue;
begin
  SetFileNameAndPrefix();

  if isEmpty(FFileName) then
    raise EPropertiesFileException.Create('FileName of ' + Self.ClassName + ' not defined!');

  if FileExists(FFileName) then
    FPropFile.LoadFromFile(FFileName);

  for vField in FRttiType.GetFields do
    if not IsIgnoreField(vField) then
    begin
      vFieldName := GetFieldName(vField);

      if IsReadOnly() and IsNotNullField(vField) then
        if isEmpty(FPropFile.PropertyItem[vFieldName]) then
          raise EPropertyItemIsNull.Create('Property Item ' + vFieldName + ' is null!');

      case vField.FieldType.TypeKind of
        tkUnknown, tkChar, tkString, tkWChar, tkLString, tkWString, tkUString:
          begin
            if not isEmpty(FPropFile.PropertyItem[vFieldName]) then
              vField.SetValue(Self, FPropFile.PropertyItem[vFieldName]);
            FFieldList.AddOrSetValue(vFieldName, vField);
          end;
        tkInteger, tkInt64:
          begin
            if not isEmpty(FPropFile.PropertyItem[vFieldName]) then
              vField.SetValue(Self, StrToIntDef(FPropFile.PropertyItem[vFieldName], 0));
            FFieldList.AddOrSetValue(vFieldName, vField);
          end;
        tkFloat:
          begin
            if not isEmpty(FPropFile.PropertyItem[vFieldName]) then
              vField.SetValue(Self, StrToFloatDef(FPropFile.PropertyItem[vFieldName], 0));
            FFieldList.AddOrSetValue(vFieldName, vField);
          end;
        tkEnumeration:
          begin
            if not isEmpty(FPropFile.PropertyItem[vFieldName]) then
              if not isEquals(vField.FieldType.Name, 'Boolean') then
              begin
                vEnumValue := vField.GetValue(Self);
                vEnumValue := TValue.FromOrdinal(vEnumValue.TypeInfo, GetEnumValue(vEnumValue.TypeInfo, FPropFile.PropertyItem[vFieldName]));
                vField.SetValue(Self, vEnumValue);
              end;
            FFieldList.AddOrSetValue(vFieldName, vField);
          end;
      end;
    end;
end;

procedure TMappedPropertiesFile.Reload;
begin
  Load();
end;

procedure TMappedPropertiesFile.Save;
begin
  if IsReadOnly() then
    raise EPropertyItemIsNull.Create('The class properties are read-only impossible to save!');
  Unload();
end;

procedure TMappedPropertiesFile.SetFileNameAndPrefix;
var
  vAttr: TCustomAttribute;
begin
  for vAttr in FRttiType.GetAttributes() do
    if vAttr is PropertiesFileAttribute then
    begin
      FFileName := ExtractFilePath(ParamStr(0)) + PropertiesFileAttribute(vAttr).FileName;
      FPrefix := PropertiesFileAttribute(vAttr).Prefix;
      Break;
    end;
end;

procedure TMappedPropertiesFile.Unload;
var
  vFld: TPair<string, TRttiField>;
begin
  if not IsReadOnly() then
  begin
    for vFld in FFieldList do
      FPropFile.PropertyItem[vFld.Key] := vFld.Value.GetValue(Self).ToString;
    FPropFile.SaveToFile(FFileName);
  end;
end;

end.
