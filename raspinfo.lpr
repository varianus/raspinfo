program raspinfo;

{$mode objfpc}{$H+}

uses {$IFDEF UNIX}
  cthreads, {$ENDIF}
  Classes,
  SysUtils,
  CustApp,
  Process { you can add units after this },
  ctypes,
  ncurses;

Const
  AppVersion = '0.1';

type
  TRenderMode = (rmKeyValue, rmText);

  TViewKind = (vkClocks, vkConfig, vkVoltage, vkCodecs, vkTemperature, vkOthers, vkAbout);
  { TRaspInfo }

  TRaspInfo = class(TCustomApplication)
  private
    Data: TStringList;
    ViewKind: TViewKind;
    MaxCols, MaxRows: integer;
    procedure DumpInfo;
    function FormatFreq(const v: string): string;
    function GetValue(const Command: string; const param: array of string): string;
    procedure LoadClocks;
    procedure LoadCodecs;
    procedure LoadConfig;
    procedure LoadTemp;
    procedure LoadOther;
    procedure LoadVolts;
    procedure RenderStatusBar;
    procedure RenderText(Mode: TRenderMode; VirtualPos: integer; RealPos: integer);
    function StripName(const v: string): string;
  protected
    procedure DoRun; override;
    procedure HandleException(Sender: TObject); override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
  end;

  { TRaspInfo }
type
  functionKey = record
    KeyLabel: string;
    key: CHType;
    Desc: string;
  end;

const
  FunctionKeys: array [0..6] of functionKey = (
    (KeyLabel: 'F2'; Key: KEY_F2; Desc: 'Temperature'),
    (KeyLabel: 'F3'; Key: KEY_F3; Desc: 'Clocks'),
    (KeyLabel: 'F4'; Key: KEY_F4; Desc: 'Settings'),
    (KeyLabel: 'F5'; Key: KEY_F5; Desc: 'Voltages'),
    (KeyLabel: 'F6'; Key: KEY_F6; Desc: 'Codecs'),
    (KeyLabel: 'F7'; Key: KEY_F7; Desc: 'Others'),
    (KeyLabel: 'F10'; Key: KEY_F10; Desc: 'Exit'));

const
  VC = 'vcgencmd';
const
  READ_BYTES = 2048;

function TRaspInfo.GetValue(const Command: string; const param: array of string): string;
var
  AProcess: TProcess;
  M: TStringStream;
  n, BytesRead: integer;
begin
  AProcess := TProcess.Create(nil);
  AProcess.Executable := Command;
  AProcess.Parameters.AddStrings(param);
  AProcess.Options    := AProcess.Options + [poUsePipes, poStdErrToOutput];
  AProcess.ShowWindow := swoHIDE;
  AProcess.Execute;

  M := TStringStream.Create;
  BytesRead := 0;

  while AProcess.Running do
  begin
    // make sure we have room
    M.SetSize(BytesRead + READ_BYTES);

    // try reading it
    n := AProcess.Output.Read((M.Memory + BytesRead)^, READ_BYTES);
    if n > 0 then
    begin
      Inc(BytesRead, n);
    end
    else
    begin
      // no data, wait 100 ms
      Sleep(10);
    end;
  end;

  // read last part
  repeat
    // make sure we have room
    M.SetSize(BytesRead + READ_BYTES);

    // try reading it
    n := AProcess.Output.Read((M.Memory + BytesRead)^, READ_BYTES);
    if n > 0 then
    begin
      Inc(BytesRead, n);
    end;
  until n <= 0;
  M.SetSize(BytesRead);

  try
    m.Position := 0;
    Result     := M.DataString;
  except
    Result := '';
  end;

  M.Free;
  AProcess.Free;

end;

function TRaspInfo.FormatFreq(const v: string): string;
var
  fx: int64;
begin
  fx     := StrToInt64Def(stripName(v), 0);
  Result := Format('%8.2n Ghz', [fx / 1000000]);
end;

function TRaspInfo.StripName(const v: string): string;
var
  tmp: string;
begin
  tmp := copy(v, pos('=', v) + 1);
  Delete(tmp, length(tmp), 1);
  Result := tmp;
end;

procedure TRaspInfo.RenderStatusBar;
var
  i: integer;
  x: smallint;
begin
  attron(COLOR_PAIR(2));
  mvhline(MaxRows - 1, 0, $20, MaxCols);
  x := 0;
  for i := 0 to Length(FunctionKeys) - 1 do
  begin
    attron(COLOR_PAIR(4));
    mvaddstr(MaxRows - 1, x, PChar(FunctionKeys[i].KeyLabel));
    x += Length(FunctionKeys[i].KeyLabel);
    attron(COLOR_PAIR(5));
    mvaddstr(MaxRows - 1, x, PChar(FunctionKeys[i].Desc));
    x += Length(FunctionKeys[i].Desc);
  end;
end;

procedure TRaspInfo.RenderText(Mode: TRenderMode; VirtualPos: integer; RealPos: integer);
var
  i, row: integer;
  MaxWidth: integer;
const
  OFFSET = 1;
begin
  MaxWidth := 0;
  attron(COLOR_PAIR(2));

  if Mode = rmKeyValue then
    for i := virtualpos to Data.Count - 1 do
      if Length(Data.Names[i]) > MaxWidth then
        MaxWidth := Length(Data.Names[i]);

  for i := virtualpos to Data.Count - 1 do
  begin
    Row := RealPos + i - VirtualPos;
    if (VirtualPos > 0) and (i = virtualpos) then
    begin
      attron(COLOR_PAIR(3));
      mvaddch(row, OFFSET - 1, ACS_UARROW);
    end;
    if Row > MaxRows - 2 then
    begin
      if i <> Data.Count - 1 then
      begin
        attron(COLOR_PAIR(3));
        mvaddch(row - 1, OFFSET - 1, ACS_DARROW);
      end;
      break;
    end;
    case Mode of
      rmKeyValue:
      begin
        if (Data.Names[I] = '') and (Data.ValueFromIndex[i] = '') then
          continue;

        attron(COLOR_PAIR(2));
        mvprintw(row, OFFSET, PChar(Data.Names[i] + ':'));
        attron(COLOR_PAIR(2));
        attron(A_BOLD);
        mvprintw(row, MaxWidth + OFFSET + 2, PChar(Data.ValueFromIndex[i]));
        attroff(A_BOLD);
      end;

      rmText:
      begin
        attron(COLOR_PAIR(2));
        mvprintw(Row, OFFSET, PChar(Data[i]));

      end;
    end;
  end;
end;

procedure TRaspInfo.LoadConfig;
begin
  Data.Text := GetValue(VC,['get_config', 'str']) + GetValue(VC,['get_config', 'int']);
end;

procedure TRaspInfo.LoadClocks;
begin
  Data.Clear;
  Data.AddPair('ARM cores', formatfreq(GetValue(VC,['measure_clock', 'arm'])));
  Data.AddPair('VC4 scaler cores', formatfreq(GetValue(VC,['measure_clock', 'core'])));
  Data.AddPair('H264 block', formatfreq(GetValue(VC,['measure_clock', 'H264'])));
  Data.AddPair('Image Signal Processor', formatfreq(GetValue(VC,['measure_clock', 'isp'])));
  Data.AddPair('3D block', formatfreq(GetValue(VC,['measure_clock', 'v3d'])));
  Data.AddPair('UART', formatfreq(GetValue(VC,['measure_clock', 'uart'])));
  Data.AddPair('PWM block (analogue audio output)', formatfreq(GetValue(VC,['measure_clock', 'pwm'])));
  Data.AddPair('SD card interface', formatfreq(GetValue(VC,['measure_clock', 'emmc'])));
  Data.AddPair('Pixel valve', formatfreq(GetValue(VC,['measure_clock', 'pixel'])));
  Data.AddPair('Analogue video encoder', formatfreq(GetValue(VC,['measure_clock', 'vec'])));
  Data.AddPair('HDMI', formatfreq(GetValue(VC,['measure_clock', 'hdmi'])));
  Data.AddPair('Display Peripheral Interface', formatfreq(GetValue(VC,['measure_clock', 'dpi'])));

end;

procedure TRaspInfo.LoadVolts;
begin
  Data.Clear;
  Data.AddPair('VC4 core voltage', StripName(GetValue(VC,['measure_volts', 'core'])));
  Data.AddPair('sdram_c', StripName(GetValue(VC,['measure_volts', 'sdram_c'])));
  Data.AddPair('sdram_i', StripName(GetValue(VC,['measure_volts', 'sdram_i'])));
  Data.AddPair('sdram_p', StripName(GetValue(VC,['measure_clock', 'sdram_p'])));
end;

procedure TRaspInfo.LoadTemp;
type
  bit = 0..1;
  TFlag = packed record
    case integer of
      0: (full: dword);
      1: (oneBit: bitpacked array[0..31] of bit);
  end;

var
  Mask: string;
  IntMask: TFlag;

begin
  Data.Clear;
  Data.AddPair('Core Temperature', StripName(GetValue(VC,['measure_temp'])));
  Data.Add('');
  Mask := StripName(GetValue(VC,['get_throttled']));
  Data.AddPair('Throttled mask', mask);
  Data.add('');
  Mask := StringReplace(MAsk, '0x', '$', []);
  intMask.full := StrToIntdef(Mask, 0);
  if intMask.Full = 0 then
  begin
    Data.Add('No throttling detected');
    exit;
  end;
  if intmask.oneBit[0] = 1 then
    Data.add('Under-voltage detected');
  if intmask.oneBit[1] = 1 then
    Data.add('Arm frequency capped');
  if intmask.oneBit[2] = 1 then
    Data.add('Currently throttled');
  if intmask.oneBit[3] = 1 then
    Data.add('Soft temperature limit active');
  if intmask.oneBit[16] = 1 then
    Data.add('Under-voltage has occurred');
  if intmask.oneBit[17] = 1 then
    Data.add('Arm frequency capping has occurred');
  if intmask.oneBit[18] = 1 then
    Data.add('Throttling has occurred');
  if intmask.oneBit[19] = 1 then
    Data.add('Soft temperature limit has occurred');

end;

function ValueAsBool(const s: string): boolean; inline;
begin
  Result := s = '1';
end;

procedure TRaspInfo.LoadOther;
begin
  Data.Clear;
  Data.AddPair('Host Name', StripName(GetValue('uname' ,['-n'])));
  Data.AddPair('Kernel version', StripName(GetValue('uname' ,['-r'])));
  Data.add('');
  Data.AddPair('Screen info', StripName(GetValue(VC,['get_lcd_info'])));
  Data.AddPair('GPU Memory', StripName(GetValue(VC,['get_mem', 'gpu'])));
  Data.AddPair('Camera enabled', BoolToStr(ValueAsBool(StripName(GetValue(VC,['get_camera'])))));
  Data.AddPair('HDMI 1 powered', BoolToStr(ValueAsBool(StripName(GetValue(VC,['display_power', '-1','2'])))));
  Data.AddPair('HDMI 2 powered', BoolToStr(ValueAsBool(StripName(GetValue(VC,['display_power', '-1','7'])))));
end;

procedure TRaspInfo.LoadCodecs;
begin
  Data.Clear;
  Data.add(GetValue(VC,['codec_enabled', 'AGIF']));
  Data.add(GetValue(VC,['codec_enabled', 'FLAC']));
  Data.add(GetValue(VC,['codec_enabled', 'H263']));
  Data.add(GetValue(VC,['codec_enabled', 'H264']));
  Data.add(GetValue(VC,['codec_enabled', 'MJPA']));
  Data.add(GetValue(VC,['codec_enabled', 'MJPB']));
  Data.add(GetValue(VC,['codec_enabled', 'MJPG']));
  Data.add(GetValue(VC,['codec_enabled', 'MPG2']));
  Data.add(GetValue(VC,['codec_enabled', 'MPG4']));
  Data.add(GetValue(VC,['codec_enabled', 'MVC0']));
  Data.add(GetValue(VC,['codec_enabled', 'PCM']));
  Data.add(GetValue(VC,['codec_enabled', 'THRA']));
  Data.add(GetValue(VC,['codec_enabled', 'VORB']));
  Data.add(GetValue(VC,['codec_enabled', 'VP6']));
  Data.add(GetValue(VC,['codec_enabled', 'VP8']));
  Data.add(GetValue(VC,['codec_enabled', 'WMV9']));
  Data.add(GetValue(VC,['codec_enabled', 'WVC1']));
end;

function setlocale(category: cint; locale: PChar): PChar; cdecl; external 'c' Name 'setlocale';

procedure TRaspInfo.DumpInfo;
var
  f: Text;
  tmpS: string;
begin
  Data     := TStringList.Create;
  TmpS := GetOptionValue('d','dump');
  if trim(tmps) ='' then
    f := StdOut
  else
    begin
      AssignFile(f, tmps);
      Rewrite(f);
    end;
  LoadTemp;
  WriteLn(f,'[Temperature]');
  WriteLn(f,Data.Text);
  LoadClocks;
  WriteLn(f,'[Clocks]');
  WriteLn(f,Data.Text);
  LoadVolts;
  WriteLn(f,'[Voltage]');
  WriteLn(f,Data.Text);
  LoadConfig;
  WriteLn(f,'[Configuration]');
  WriteLn(f,Data.Text);
  LoadOther;
  WriteLn(f,'[Other]');
  WriteLn(f,Data.Text);
  if tmpS <> '' then
    CloseFile(f);
  Data.free;
end;

procedure TRaspInfo.DoRun;
var
  ErrorMsg: string;
var
  ch: longint = 0;
  pad: PWINDOW;
  tmpS:string;
  my_bg: smallint = COLOR_BLACK;
  VirtualPos: integer;
  Ok: integer;
  event: MEVENT;
  tmp, i: integer;
  Refresh: longint;
begin
  Refresh := 10;
  // quick check parameters
  ErrorMsg := CheckOptions('hu:d::', 'help update: dump::', true);
  if ErrorMsg <> '' then
  begin
    Writeln(ErrorMsg);
    Terminate;
    Exit;
  end;

  // parse parameters
  if HasOption('h', 'help') then
  begin
    WriteHelp;
    Terminate;
    Exit;
  end;
  if HasOption('d', 'dump') then
  begin
    DumpInfo;
    Terminate;
    exit;
  end;

  if HasOption('u', 'update') then
  begin
    TmpS := GetOptionValue('u','update');
    if not TryStrToInt(tmpS, Refresh) then
    begin
      WriteLn('Invalid refresh parameter');
      Terminate;
      exit;
    end
  end;

  { add your program here }
  Data     := TStringList.Create;
  setlocale(1, 'UTF-8');
  initscr();
  noecho();
  keypad(stdscr, True);
  curs_set(0);
  Clear();
  halfdelay(refresh);
  mousemask($ffffffff, nil);
  if has_colors() then
  begin
    start_color();
    if (use_default_colors() = OK) then
      my_bg := -1
    else
      my_bg := COLOR_BLACK;
    init_pair(1, COLOR_YELLOW, my_bg);
    init_pair(2, COLOR_WHITE, my_bg);
    init_pair(3, my_bg, COLOR_WHITE);
    init_pair(4, COLOR_WHITE, my_bg);
    init_pair(5, COLOR_BLACK, COLOR_CYAN);
  end;

  ch := Key_F2;
  try
    while ch <> KEY_F10 do
    begin
      getmaxyx(stdscr, MaxRows, MaxCols);
      Clear();
      RenderStatusBar;
      attron(COLOR_PAIR(3));
      mvhline(0, 0, $20, MaxCols);
      mvprintw(0, 0, 'Raspinfo');
      if ch = KEY_MOUSE then
      begin
        ok := getmouse(@Event);
        if boolean(event.bstate and BUTTON1_CLICKED) then
          if (event.y = MaxRows - 1) then
          begin
            tmp := 0;
            for i := 0 to length(FunctionKeys) - 1 do
            begin
              tmp := tmp + Length(FunctionKeys[i].KeyLabel) + Length(FunctionKeys[i].Desc);
              if event.x < tmp then
              begin
                ch := FunctionKeys[i].Key;

                doupdate;
                break;
              end;
            end;

          end;
      end;
      case ch of
        KEY_F2:
        begin
          ViewKind   := vkTemperature;
          VirtualPos := 0;
        end;
        KEY_F3:
        begin
          ViewKind   := vkClocks;
          virtualPos := 0;
        end;
        KEY_F4:
        begin
          ViewKind := vkConfig;
          LoadConfig;
          VirtualPos := 0;
        end;
        KEY_F5:
        begin
          ViewKind   := vkVoltage;
          VirtualPos := 0;
        end;
        KEY_F6:
        begin
          ViewKind := vkCodecs;
          LoadCodecs;
          VirtualPos := 0;
        end;
        KEY_F7:
        begin
          ViewKind := vkOthers;
          LoadOther;
          VirtualPos := 0;
        end;
        KEY_F10:
        begin
          Terminate;
          exit;
        end;

        KEY_DOWN: if VirtualPos < (Data.Count - (MaxRows - 2)) then
            Inc(VirtualPos);
        KEY_UP: if VirtualPos > 0 then
            Dec(VirtualPos);

      end;
      case ViewKind of
        vkClocks:
        begin
          LoadClocks;
          RenderText(rmKeyValue, VirtualPos, 2);
          halfdelay(Refresh);
        end;

        vkVoltage:
        begin
          LoadVolts;
          RenderText(rmKeyValue, VirtualPos, 2);
          halfdelay(Refresh);
        end;

        vkCodecs, vkConfig, vkOthers:
        begin
          RenderText(rmKeyValue, VirtualPos, 2);
          cbreak;
        end;
        vkTemperature:
        begin
          LoadTemp;
          RenderText(rmKeyValue, VirtualPos, 2);
          halfdelay(Refresh);
        end;
      end;
      attron(COLOR_PAIR(1));
      doupdate();
      ch := getch();
    end;

  finally
    endwin();
    Data.Free;
  end;


  // stop program loop
  Terminate;
end;

procedure TRaspInfo.HandleException(Sender: TObject);
var
  I: Integer;
  Frames: PPointer;
  Report: string;
  e: exception;
begin
  Report := 'Program exception! ' + LineEnding +
    'Stacktrace:' + LineEnding + LineEnding;
  e:= Exception(ExceptObject);
  if E <> nil then begin
    Report := Report + 'Exception class: ' + E.ClassName + LineEnding +
    'Message: ' + E.Message + LineEnding;
  end;
  Report := Report + BackTraceStrFunc(ExceptAddr);
  Frames := ExceptFrames;
  for I := 0 to ExceptFrameCount - 1 do
    Report := Report + LineEnding + BackTraceStrFunc(Frames[I]);
  writeln(stderr, report);
end;

constructor TRaspInfo.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException := True;
end;

destructor TRaspInfo.Destroy;
begin
  inherited Destroy;
end;

procedure TRaspInfo.WriteHelp;
begin
  { add your help code here }
  writeln('raspinfo ' + AppVersion);
  writeln('This is an interactive application to show some info about your Raspberry Pi');
  writeln('Usage: raspinfo [option]');
  writeln;
  writeln('-u <delay>, --update=<delay>' + sLineBreak +
          '    ' + ' Delay between updates, in tenths of seconds (default 10, i.e. one second');
  writeln('-d [filename], --dump[=filename]' + sLineBreak +
          '    ' + 'Dump all information to stodout or to a specified file');

end;

var
  Application: TRaspInfo;
begin
  Application := TRaspInfo.Create(nil);
  Application.Title := 'RaspInfo';
  Application.Run;
  Application.Free;
end.
