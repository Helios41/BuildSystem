#include <stdio.h>

#if 0
//this makes it work but i dont like it
__declspec(dllexport) int add_integers_foo(int num1, int num2)
#else
int add_integers_foo(int num1, int num2)
#endif
{
   printf("Added: %u\n", num1 + num2);
   return num1 + num2;
}