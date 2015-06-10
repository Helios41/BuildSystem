#include <stdio.h>
#include <Windows.h>

int main()
{
  MessageBox(NULL, TEXT("Text"), TEXT("Title"), MB_ICONWARNING);
  printf("Hello world\n");
  return 0;
}