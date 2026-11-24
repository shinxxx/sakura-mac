// C++ のアウトライン解析のサンプル（第 42 步）
#include <string>
#include <vector>

namespace outer {
namespace inner {

class Shape {
public:
	Shape();
	virtual ~Shape();
	virtual double Area() const = 0;
	int Count() const { return m_count; }
	Shape& operator=(const Shape& other);
	operator bool() const { return true; }
private:
	int m_count;
	struct Point { int x; int y; };
	enum Kind { Circle, Square };
};

Shape::Shape() : m_count(0)
{
	if (m_count > 0) { m_count = 1; }
}

Shape::~Shape()
{
}

Shape& Shape::operator=(const Shape& other)
{
	m_count = other.m_count;	// "{" の文字列 '}'
	return *this;
}

template <typename T>
T Max(T a, T b) { return a > b ? a : b; }

} // namespace inner

struct Pair {
	int first, second;
	void Swap();
};

void Pair::Swap()
{
	int t = first; first = second; second = t;
}

union Value { int i; double d; };

} // namespace outer

/* コメントの中の関数 void NotFunc() { } */
#if 0
void Disabled() {}
#endif

static int helper(int x);
extern "C" int c_api(const char* s);

int helper(int x)
{
	auto lambda = [](int y) { return y * 2; };
	return lambda(x);
}

std::vector<std::string> outer::inner::Split(const std::string& s, char c)
{
	return {};
}

class Outer {
	class Nested {
		void Method() {}
	};
};

void Outer::Nested::Method2() {}

int 日本語関数(int 引数)
{
	return 引数;
}

int main(int argc, char* argv[])
{
	return helper(argc);
}
