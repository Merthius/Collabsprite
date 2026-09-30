// No injection/subclassing of Aseprite: a temporary Windows drop surface is
// visible only while an external drag enters the exact board client area.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public static class CollabspriteFiles {
  public delegate bool WindowCallback(IntPtr h, IntPtr state);
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
  [DllImport("user32.dll")] static extern bool EnumWindows(WindowCallback fn,IntPtr state);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder text,int count);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out Rect rect);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h,ref Point point);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h,uint flag);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll")] static extern IntPtr PostMessage(IntPtr h,uint message,IntPtr w,IntPtr l);
  static string Title(IntPtr h) {
    var text=new StringBuilder(256);GetWindowText(h,text,text.Capacity);return text.ToString();
  }
  static IntPtr Find(string token) {
    string title="Collabsprite - Ideenwand #"+token.Substring(0,12);
    IntPtr match=IntPtr.Zero;int count=0;
    EnumWindows(delegate(IntPtr h,IntPtr state) {
      if(IsWindowVisible(h) && Title(h)==title) {
        uint pid;GetWindowThreadProcessId(h,out pid);
        try { using(var p=Process.GetProcessById((int)pid)) {
          if(!p.ProcessName.Equals("aseprite",StringComparison.OrdinalIgnoreCase)) return true;
        }} catch { return true; }
        match=h;count++;
      }
      return true;
    },IntPtr.Zero);
    return count==1 ? match : IntPtr.Zero;
  }
  public static bool Supported(string path) {
    string ext=Path.GetExtension(path).ToLowerInvariant();
    return ext==".png" || ext==".jpg" || ext==".jpeg" || ext==".gif" || ext==".bmp" || ext==".webp";
  }
  public static string[] Validate(string[] paths) {
    if(paths==null || paths.Length<1 || paths.Length>32) throw new Exception("Bitte höchstens 32 Bilder auswählen.");
    foreach(string path in paths) {
      if(!Supported(path) || !Path.IsPathRooted(path) || !File.Exists(path) || new FileInfo(path).Length>64*1024*1024)
        throw new Exception("Bitte Bilddateien bis 64 MiB auswählen (PNG, JPG, WebP, GIF, BMP).");
    }
    return paths;
  }
  public static void Write(string token,object data) {
    string path=Path.Combine(Path.GetTempPath(),"Collabsprite-files-"+token+".json");
    string raw=new JavaScriptSerializer().Serialize(data);
    if(Encoding.UTF8.GetByteCount(raw)>256*1024) throw new Exception("Bildauswahl ist zu groß.");
    string staging=path+"."+Guid.NewGuid().ToString("N")+".tmp";
    try { File.WriteAllText(staging,raw,new UTF8Encoding(false));File.Move(staging,path); }
    finally { if(File.Exists(staging)) File.Delete(staging); }
  }
  static object Result(string status,string[] paths,double x,double y) {
    return new { id=Guid.NewGuid().ToString("N"),status=status,paths=paths,x=x,y=y };
  }
  public static object FileDrop(IDataObject data,Rectangle bounds,int x,int y) {
    return Result("ok",Validate(data.GetData(DataFormats.FileDrop) as string[]),
      Math.Max(0,Math.Min(1,(x-bounds.Left)/(double)Math.Max(1,bounds.Width))),
      Math.Max(0,Math.Min(1,(y-bounds.Top)/(double)Math.Max(1,bounds.Height))));
  }
  class Owner : IWin32Window {
    public IntPtr Handle { get;private set; }
    public Owner(IntPtr h) { Handle=h; }
  }
  class DropSurface : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
      get { var p=base.CreateParams;p.ExStyle|=0x08000000|0x80;return p; }
    }
  }
  public static void Run(string mode,string token,string boardToken) {
    Application.EnableVisualStyles();
    IntPtr board=Find(boardToken);
    if(board==IntPtr.Zero) { Write(token,Result("error",null,0,0));return; }
    if(mode=="Pick") {
      using(var picker=new OpenFileDialog()) {
        picker.Title="Referenzbilder auswählen";picker.Multiselect=true;
        picker.Filter="Bilder|*.png;*.jpg;*.jpeg;*.webp;*.gif;*.bmp";
        picker.CheckFileExists=true;picker.CheckPathExists=true;
        using(var watch=new Timer()) {
        watch.Interval=200;watch.Tick+=delegate {
          if(IsWindow(board)) return;
          int current=Process.GetCurrentProcess().Id;
          EnumWindows(delegate(IntPtr h,IntPtr state) {
            uint pid;GetWindowThreadProcessId(h,out pid);
            if(pid==(uint)current && Title(h)==picker.Title) PostMessage(h,0x10,IntPtr.Zero,IntPtr.Zero);
            return true;
          },IntPtr.Zero);
        };
        watch.Start();
        try {
          bool ok=picker.ShowDialog(new Owner(board))==DialogResult.OK;
          if(IsWindow(board)) Write(token,Result(ok ? "ok" : "cancel",ok ? Validate(picker.FileNames) : null,0,0));
        } catch { if(IsWindow(board)) Write(token,Result("error",null,0,0)); }
        finally { watch.Stop(); }
        }
      }
      return;
    }
    using(var layer=new DropSurface()) using(var timer=new Timer()) {
      layer.FormBorderStyle=FormBorderStyle.None;layer.ShowInTaskbar=false;
      layer.Opacity=0.01;layer.BackColor=Color.Black;layer.AllowDrop=true;layer.TopMost=true;
      var pending=new Queue<object>();bool down=false,external=false;
      layer.DragEnter+=delegate(object sender,DragEventArgs e) {
        e.Effect=e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
      };
      layer.DragOver+=delegate(object sender,DragEventArgs e) {
        e.Effect=e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
      };
      layer.DragLeave+=delegate { layer.Hide(); };
      layer.DragDrop+=delegate(object sender,DragEventArgs e) {
        try {
          if(pending.Count<8) pending.Enqueue(FileDrop(e.Data,layer.Bounds,e.X,e.Y));
        } catch { if(pending.Count<8) pending.Enqueue(Result("error",null,0,0)); }
        layer.Hide();external=false;
      };
      timer.Interval=80;
      timer.Tick+=delegate {
        if(!IsWindow(board) || Title(board)!="Collabsprite - Ideenwand #"+boardToken.Substring(0,12)) {
          timer.Stop();layer.Hide();Application.ExitThread();return;
        }
        string mailbox=Path.Combine(Path.GetTempPath(),"Collabsprite-files-"+token+".json");
        if(pending.Count>0 && !File.Exists(mailbox)) {
          try { Write(token,pending.Peek());pending.Dequeue(); } catch { }
        }
        bool pressed=(GetAsyncKeyState(1)&0x8000)!=0;
        var pointer=Cursor.Position;
        if(pressed && !down) external=GetAncestor(WindowFromPoint(pointer),2)!=board;
        down=pressed;
        if(!pressed) { external=false;layer.Hide();return; }
        if(!external || !IsWindowVisible(board)) return;
        Rect r;GetClientRect(board,out r);var origin=new Point(0,0);ClientToScreen(board,ref origin);
        var bounds=new Rectangle(origin.X,origin.Y,r.Right-r.Left,r.Bottom-r.Top);
        IntPtr under=GetAncestor(WindowFromPoint(pointer),2);
        if(bounds.Contains(pointer) && (under==board || under==layer.Handle)) {
          layer.Bounds=bounds;if(!layer.Visible) layer.Show(new Owner(board));
        } else layer.Hide();
      };
      timer.Start();Application.Run();
      string leftover=Path.Combine(Path.GetTempPath(),"Collabsprite-files-"+token+".json");
      if(File.Exists(leftover)) File.Delete(leftover);
    }
  }
}
