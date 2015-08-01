#include <stdio.h>
#include <Windows.h>
#include "remote_file.c"

typedef int (*add_integers_foo_t)(int num1, int num2);
void print_a_message(void);

int main()
{
  MessageBox(NULL, TEXT("Text"), TEXT("Title"), MB_ICONWARNING);
  printf("Hello world\n");
  
  print_a_string("HELLO!");
  print_a_message();
  
  char LibraryPath[250];
  
  printf("Enter Library Path:\n");
  fgets(LibraryPath, 250, stdin);
  LibraryPath[strlen(LibraryPath) - 1] = '\0';
  printf("Loading %s\n", LibraryPath);
  
  HINSTANCE DLibraryHandle = LoadLibraryA(LibraryPath);
  add_integers_foo_t add_integers_foo = NULL;
  
  if(DLibraryHandle == NULL)
  {
     printf("Library not found!\n");
     printf("%u\n", GetLastError());
  }
  else
  {
     printf("Library found!\n");
     
     add_integers_foo = (add_integers_foo_t) GetProcAddress(DLibraryHandle, "add_integers_foo");
  }
  
  
  if(add_integers_foo == NULL)
  {
     printf("Function not found!\n");
     printf("%u\n", GetLastError());
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