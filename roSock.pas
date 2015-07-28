unit roSock;

interface

uses SysUtils, Classes;

{xxx$D-}
{xxx$L-}

type
  PSocketAddress=^TSocketAddress;
  TSocketAddress=record
    family: word;
    port: word;
    data1,data2,data3,data4:cardinal;
  end;

  THostEntry=record
    h_name:PAnsiChar;
    h_aliases:^PAnsiChar;
    h_addrtype:word;
    h_length:word;
    h_addr:^PAnsiChar;
    //TODO: IPv6
  end;
  PHostEntry = ^THostEntry;

  TFDSet = record
    fd_count: cardinal;
    fd_array: array[0..63] of THandle;
  end;
  PFDSet = ^TFDSet;

  TTimeVal = record
    tv_sec: cardinal;
    tv_usec: cardinal;
  end;
  PTimeVal = ^TTimeVal;

const
  INVALID_SOCKET = THandle(not(0));
  AF_INET = 2;
  AF_INET6 = 23;
  SOCKET_ERROR = -1;
  SOCK_STREAM = 1;
  IPPROTO_IP = 0;
  SOMAXCONN = 5;
  SOL_SOCKET = $FFFF;
  SO_REUSEADDR = $0004;
  SO_SNDBUF = $1001;
  SO_RCVBUF = $1002;
  SO_SNDTIMEO = $1005;
  SO_RCVTIMEO = $1006;
  SD_BOTH = 2;
  IPPROTO_TCP = 6;
  TCP_NODELAY = 1;

  //messages for feedback (WM_USER or ...)
  WM_TCP_ERROR      =$0401;
  WM_TCP_CONNECT    =$0402;
  WM_TCP_DISCONNECT =$0403;
  WM_TCP_DATA       =$0404;

type
  TTcpSocket=class(TObject)
  private
    FSocket:THandle;
    FAddr:TSocketAddress;
    FConnected:boolean;
    function GetSocketName: TSocketAddress;
    function GetLocalHostName: string;
    function GetLocalAddress:string;
    function GetLocalPort: word;
  protected
    constructor Create(family: word; ASocket:THandle); overload;
    function GetPort:word;
    function GetAddress:string;
    function GetHostName:string;
  public
    constructor Create(family: word= AF_INET); overload;
    destructor Destroy; override;
    procedure Connect(const Address:AnsiString;Port:word);
    procedure Disconnect;
    function ReceiveBuf(var Buf; BufSize: Integer): Integer;
    function SendBuf(const Buffer; Count: LongInt): LongInt;
    property Handle:THandle read FSocket;
    property Connected:boolean read FConnected;
    property Port:word read GetPort;
    property Address:string read GetAddress;
    property HostName:string read GetHostName;
    property LocalHostName:string read GetLocalHostName;
    property LocalAddress:string read GetLocalAddress;
    property LocalPort:word read GetLocalPort;
  end;

  TTcpServer=class(TObject)
  private
    FFamily: word;
    FSocket: THandle;
  public
    constructor Create(family: word= AF_INET);
    destructor Destroy; override;
    procedure Bind(const Address:AnsiString;Port:word);
    procedure Listen;
    procedure WaitForConnection;
    function Accept:TTcpSocket;
    property Handle:THandle read FSocket;
  end;

  ETcpSocketError=class(Exception);

  TTcpThread=class(TThread)
  private
    FSocket:TTcpSocket;
    FHandle:THandle;
    FHost:string;
    FPort:word;
  protected
    procedure Execute; override;
  public
    constructor Create(Socket:TTcpSocket;Handle:THandle;
      const Host:string;Port:word);
  end;

function WSAStartup(wVersionRequired: word; WSData: pointer): integer; stdcall;
function WSACleanup: integer; stdcall;
function WSAGetLastError: integer; stdcall;
function htons(hostshort: word): word; stdcall;
function inet_addr(cp: PAnsiChar): cardinal; stdcall;
function inet_ntoa(inaddr: cardinal): PAnsiChar; stdcall;
function gethostbyaddr(addr: pointer; len, Struct: integer): PHostEntry; stdcall;
function gethostbyname(name: PAnsiChar): PHostEntry; stdcall;
function getsockname(s: THandle; var name: TSocketAddress; var namelen: Integer): Integer; stdcall;
//TODO: getaddrinfo
function socket(af, Struct, protocol: integer): THandle; stdcall;
function setsockopt(s: THandle; level, optname: integer; optval: PAnsiChar;
  optlen: integer): integer; stdcall;
function listen(socket: THandle; backlog: integer): integer; stdcall;
function bind(s: THandle; var addr: TSocketAddress; namelen: integer): integer; stdcall;
function accept(s: THandle; addr: PSocketAddress; addrlen: PInteger): THandle; stdcall;
function connect(s: THandle; var name: TSocketAddress; namelen: integer): integer; stdcall;
function recv(s: THandle; var Buf; len, flags: integer): integer; stdcall;
function select(nfds: integer; readfds, writefds, exceptfds: PFDSet;
  timeout: PTimeVal): integer; stdcall;
function send(s: THandle; var Buf; len, flags: integer): integer; stdcall;
function shutdown(s: THandle; how: integer): integer; stdcall;
function closesocket(s: THandle): integer; stdcall;
//function __WSAFDIsSet(s: THandle; var FDSet: TFDSet): Boolean; stdcall;

implementation

uses Windows;

var
  WSAData:record // !!! also WSDATA
    wVersion:word;
    wHighVersion:word;
    szDescription:array[0..256] of AnsiChar;
    szSystemStatus:array[0..128] of AnsiChar;
    iMaxSockets:word;
    iMaxUdpDg:word;
    lpVendorInfo:PAnsiChar;
  end;

procedure RaiseLastWSAError;
begin
  raise ETcpSocketError.Create(SysErrorMessage(WSAGetLastError));
end;

procedure PrepareSockAddr(var addr: TSocketAddress; family, port: word;
  const host: AnsiString);
var
  e:PHostEntry;
begin
  addr.family:=family;//AF_INET
  addr.port:=htons(port);
  addr.data1:=0;
  addr.data2:=0;
  addr.data3:=0;
  addr.data4:=0;
  if host<>'' then
    if host[1] in ['0'..'9'] then
      addr.data1:=inet_addr(PAnsiChar(host))
    else
     begin
      //TODO: getaddrinfo
      e:=gethostbyname(PAnsiChar(host));
      if e=nil then RaiseLastWSAError;
      addr.family:=e.h_addrtype;
      Move(e.h_addr^[0],addr.data1,e.h_length);
     end;
end;

{ TTcpSocket }

procedure TTcpSocket.Connect(const Address: AnsiString; Port: word);
begin
  PrepareSockAddr(FAddr,FAddr.family,Port,Address);
  if roSock.connect(FSocket,FAddr,SizeOf(TSocketAddress))=SOCKET_ERROR then
    RaiseLastWSAError
  else
    FConnected:=true;
end;

constructor TTcpSocket.Create(family: word);
begin
  inherited Create;
  FConnected:=false;
  FAddr.family:=family;//AF_INET
  FSocket:=socket(family,SOCK_STREAM,IPPROTO_IP);
  if FSocket=INVALID_SOCKET then RaiseLastWSAError;
  FillChar(FAddr,SizeOf(TSocketAddress),#0);
end;

constructor TTcpSocket.Create(family: word; ASocket: THandle);
var
  i:integer;
begin
  inherited Create;
  FAddr.family:=family;
  FSocket:=ASocket;
  if FSocket=INVALID_SOCKET then RaiseLastWSAError;
  i:=1;
  if setsockopt(FSocket,IPPROTO_TCP,TCP_NODELAY,@i,4)<>0 then
    RaiseLastWSAError;
  FConnected:=true;//?
end;

destructor TTcpSocket.Destroy;
begin
  //Disconnect;?
  closesocket(FSocket);
  inherited;
end;

procedure TTcpSocket.Disconnect;
begin
  if FConnected then
   begin
    FConnected:=false;
    shutdown(FSocket,SD_BOTH);
   end;
end;

function TTcpSocket.GetPort: word;
begin
  Result:=FAddr.port;
end;

function TTcpSocket.GetAddress: string;
begin
  Result:=inet_ntoa(FAddr.data1);
end;

function SocketAddressToStr(const addr: TSocketAddress): string;
type
  TWArr=array[0..7] of word;
  PWArr=^TWArr;
var
  e:PHostEntry;
  i:integer;
  x:PWArr;
begin
  e:=gethostbyaddr(@addr.data1,SizeOf(TSocketAddress),addr.family);
  if e=nil then
    //inet_ntop?
    if addr.family=AF_INET6 then
     begin
      x:=PWArr(@addr.data1);
      if x[0]=0 then Result:=':' else
        Result:=Result+IntToHex(x[0],4)+':';
      i:=1;
      while (i<8) do
       begin
        while (i<8) and (x[i]=0) do inc(i);
        if i=8 then Result:=Result+':' else
          Result:=Result+':'+IntToHex(x[i],4);
        inc(i);
       end;
     end
    else
      Result:=inet_ntoa(addr.data1)
  else
    Result:=e.h_name;
end;

function TTcpSocket.GetHostName: string;
begin
  Result:=SocketAddressToStr(FAddr);
end;

function TTcpSocket.ReceiveBuf(var Buf; BufSize: Integer): Integer;
begin
  Result:=recv(FSocket,Buf,BufSize,0);
  if Result=SOCKET_ERROR then
    try
      RaiseLastWSAError;
    finally
      Disconnect;
    end;
end;

function TTcpSocket.SendBuf(const Buffer; Count: LongInt): LongInt;
var
  p:pointer;
begin
  p:=@Buffer;
  Result:=send(FSocket,p^,Count,0);
  if Result=SOCKET_ERROR then
    try
      RaiseLastWSAError;
    finally
      Disconnect;
    end;
end;

function TTcpSocket.GetSocketName:TSocketAddress;
var
  l:integer;
begin
  l:=SizeOf(TSocketAddress);
  FillChar(Result,l,#0);
  if getsockname(FSocket,Result,l)=SOCKET_ERROR then
    RaiseLastWSAError;
end;

function TTcpSocket.GetLocalHostName: string;
begin
  Result:=SocketAddressToStr(GetSocketName);
end;

function TTcpSocket.GetLocalAddress: string;
begin
  Result:=inet_ntoa(GetSocketName.data1);
end;

function TTcpSocket.GetLocalPort: word;
begin
  Result:=GetSocketName.port;
end;

{ TTcpServer }

constructor TTcpServer.Create(family: word);
begin
  inherited Create;
  FFamily:=family;//AF_INET
  FSocket:=socket(FFamily,SOCK_STREAM,IPPROTO_IP);
end;

destructor TTcpServer.Destroy;
begin
  closesocket(FSocket);
  inherited;
end;

procedure TTcpServer.Bind(const Address: AnsiString; Port: word);
var
  a:TSocketAddress;
begin
  if FSocket=INVALID_SOCKET then RaiseLastWSAError;
  PrepareSockAddr(a,FFamily,Port,Address);
  if roSock.bind(FSocket,a,SizeOf(TSocketAddress))=SOCKET_ERROR then
    RaiseLastWSAError;
end;

procedure TTcpServer.Listen;
begin
  //call bind first!
  if roSock.listen(FSocket,SOMAXCONN)=SOCKET_ERROR then
    RaiseLastWSAError;
end;

procedure TTcpServer.WaitForConnection;
var
  r,x:TFDSet;
begin
  r.fd_count:=1;
  r.fd_array[0]:=FSocket;
  x.fd_count:=1;
  x.fd_array[0]:=FSocket;
  if select(FSocket,@r,nil,@x,nil)=SOCKET_ERROR then RaiseLastWSAError;
  if x.fd_count=1 then //if __WSAFDIsSet(FSocket,x) then
    raise ETcpSocketError.Create('Socket in error state');//?
  if r.fd_count=0 then //if not __WSAFDIsSet(FSocket,r) then
    raise ETcpSocketError.Create('Select without error nor result');//??
end;

function TTcpServer.Accept: TTcpSocket;
var
  a:TSocketAddress;
  l:integer;
begin
  l:=SizeOf(TSocketAddress);
  FillChar(a,l,#0);
  Result:=TTcpSocket.Create(FFamily,roSock.accept(FSocket,@a,@l));
  Result.FAddr:=a;
end;

const
  winsockdll='wsock32.dll';

function WSAStartup; external winsockdll;
function WSACleanup; external winsockdll;
function WSAGetLastError; external winsockdll;
function htons; external winsockdll;
function inet_addr; external winsockdll;
function inet_ntoa; external winsockdll;
function gethostbyaddr; external winsockdll;
function gethostbyname; external winsockdll;
function getsockname; external winsockdll;
function socket; external winsockdll;
function setsockopt; external winsockdll;
function listen; external winsockdll;
function bind; external winsockdll;
function accept; external winsockdll;
function connect; external winsockdll;
function recv; external winsockdll;
function select; external winsockdll;
function send; external winsockdll;
function shutdown; external winsockdll;
function closesocket; external winsockdll;
//function __WSAFDIsSet; external winsockdll;

{ TTcpThread }

constructor TTcpThread.Create(Socket: TTcpSocket; Handle: THandle;
  const Host: string; Port: word);
begin
  inherited Create(false);
  FreeOnTerminate:=true;
  FSocket:=Socket;
  FHandle:=Handle;
  FHost:=Host;
  FPort:=Port;
end;

procedure TTcpThread.Execute;
var
  x,y:AnsiString;
begin
  try
    FSocket.Connect(FHost,FPort);
    PostMessage(FHandle,WM_TCP_CONNECT,0,0);
    while FSocket.Connected and not(Terminated) do
     begin
      SetLength(x,$10000);
      SendMessage(FHandle,WM_TCP_DATA,integer(PAnsiChar(x)),
        FSocket.ReceiveBuf(x[1],$10000));
     end;
  except
    on e:Exception do
     begin
      y:=e.Message;//e.ClassName
      SendMessage(FHandle,WM_TCP_ERROR,integer(PAnsiChar(y)),Length(y));
     end;
  end;
  try
    FSocket.Disconnect;
    PostMessage(FHandle,WM_TCP_DISCONNECT,0,0);
  except
    //silent
  end;
end;

initialization
  WSAStartup($0101,@WSAData);
finalization
  WSACleanup;
end.
