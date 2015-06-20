#include <stdio.h>
#include <Windows.h>

typedef int (*add_integers_foo_t)(int num1, int num2);

//TODO: why is library not found?

int main()
{
  MessageBox(NULL, TEXT("Text"), TEXT("Title"), MB_ICONWARNING);
  printf("Hello world\n");
  
  HINSTANCE DLibraryHandle = LoadLibrary("./DLTest.dll");
  
  if(DLibraryHandle == NULL)
  {
     printf("Library not found!\n");
  }
  else
  {
     printf("Library found!\n");
  }
     
  
  add_integers_foo_t add_integers_foo = (add_integers_foo_t) GetProcAddress(DLibraryHandle, "add_integers_foo");
  
  if(add_integers_foo == NULL)
  {
     printf("Function not found!\n");
     
     int i1 = 5;
     int i2 = 6;
     int i3 = add_integers_foo(i1, i2);
  }
  else
  {
     printf("Function found!\n");
  }
  
  return 0;
}