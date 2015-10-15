#include <stdio.h>
#include "remote_file.h"
#include <string.h>

#ifdef _WIN32
#include <Windows.h>
#else
#include <dlfcn.h>
#endif

typedef int (*add_integers_foo_t)(int num1, int num2);
void print_a_message(void);

int main()
{
#ifdef _WIN32
  MessageBox(NULL, TEXT("Text"), TEXT("Title"), MB_ICONWARNING);
#endif

  printf("Hello world\n");
  
  print_a_string("HELLO!");
  print_a_message();
  
  char LibraryPath[250];
  
  printf("Enter Library Path:\n");
  fgets(LibraryPath, 250, stdin);
  LibraryPath[strlen(LibraryPath) - 1] = '\0';
  printf("Loading %s\n", LibraryPath);
  add_integers_foo_t add_integers_foo = NULL;  

#ifdef _WIN32
  HINSTANCE DLibraryHandle = LoadLibraryA(LibraryPath);
#else
  void *DLibraryHandle = dlopen(LibraryPath, RTLD_LAZY);
#endif  

  if(DLibraryHandle == NULL)
  {
     printf("Library not found!\n");
#ifdef _WIN32
     printf("%u\n", GetLastError());
#endif
  }
  else
  {
     printf("Library found!\n");
     
#ifdef _WIN32
     add_integers_foo = (add_integers_foo_t) GetProcAddress(DLibraryHandle, "add_integers_foo");
#else
     add_integers_foo = (add_integers_foo_t) dlsym(DLibraryHandle, "add_integers_foo");
#endif
  }
  
  
  if(add_integers_foo == NULL)
  {
     printf("Function not found!\n");
#ifdef _WIN32
     printf("%u\n", GetLastError());
#endif
  }
  else
  {
     printf("Function found!\n");\
     
     int i1 = 5;
     int i2 = 6;
     int i3 = add_integers_foo(i1, i2);
  }
 
#ifdef __linux__
   if(DLibraryHandle)
   	dlclose(DLibraryHandle);
#endif 
  return 0;
}
