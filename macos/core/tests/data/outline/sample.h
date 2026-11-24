// C/C++ のヘッダー（拡張子 .h：C/C++ 自動判定）
#ifndef SAMPLE_H
#define SAMPLE_H

class Widget {
public:
	Widget();
	void Draw() const;
	inline int Width() const { return m_width; }
private:
	int m_width;
};

int free_function(int value);

inline int inline_function(int value)
{
	return value + 1;
}

#endif
