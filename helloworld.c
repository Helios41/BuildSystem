#include <stdio.h>
#include <Windows.h>

typedef int (*add_integers_foo_t)(int num1, int num2);

//TODO: why is library not found?

int main()
{
  MessageBox(NULL, TEXT("Text"), TEXT("Title"), MB_ICONWARNING);
  printf("Hello world\n");
  
  /*
  When specifying a path, be sure to use backslashes (\), not forward slashes (/)
  https://msdn.microsoft.com/en-us/library/windows/desktop/ms684175%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396
  */
  
  char LibraryPath[50];
  
  printf("Enter Library Path:\n");
  HINSTANCE DLibraryHandle = LoadLibrary(fgets(LibraryPath, 50, stdin)); //(".\DLTest.dll"); //./DLTest.dll
  add_integers_foo_t add_integers_foo = NULL;
  
  if(DLibraryHandle == NULL)
  {
     printf("Library not found!\n");
  }
  else
  {
     printf("Library found!\n");
     
     add_integers_foo = (add_integers_foo_t) GetProcAddress(DLibraryHandle, "add_integers_foo");
  }
  
  
  if(add_integers_foo == NULL)
  {
     printf("Function not found!\n");
  }
  else
  {
     printf("Function found!\n");\
     
     int i1 = 5;
     int i2 = 6;
     int i3 = add_integers_foo(i1, i2);
  }
  
  return 0;
}