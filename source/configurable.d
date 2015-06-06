module BuildSystemConfigurable;

const string GlobalConfigFilePath = "./configs/global_config.json";

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

string GetArchitectureName()
{
   version(X86) { return "X86"; }
   version(X86_64) { return "X86_64"; }
   version(ARM) { return "ARM"; }
}