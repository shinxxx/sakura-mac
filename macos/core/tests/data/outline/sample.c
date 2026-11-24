/* C のアウトライン解析のサンプル */
#include <stdio.h>

static int counter;

int add(int a, int b);
static void reset(void);

int add(int a, int b)
{
	return a + b;
}

static void reset(void)
{
	counter = 0;
}

int (*get_handler(int kind))(int)
{
	return 0;
}

struct node {
	int value;
	struct node *next;
};

int
multi_line_name(
	int a,
	int b)
{
	return a * b;
}

int main(void)
{
	printf("{ not a block }\n");
	return add(1, 2);
}
