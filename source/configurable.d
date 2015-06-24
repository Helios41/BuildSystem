module BuildSystemConfigurable;

string GetOSName()
{
   version(Windows) { return "Windows"; }
   version(linux) { return "Linux"; }
   version(OSX) { return "OSX"; }
   version(FreeBSD) { return "BSD"; }
   version(OpenBSD) { return "BSD"; }
   version(NetBSD) { return "BSD"; }
   version(DragonFlyBSD) { return "BSD"; }
   version(BSD) { return "BSD"; }
   version(Android) { return "Android"; }
}