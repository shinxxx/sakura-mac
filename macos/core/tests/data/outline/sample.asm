; アセンブラのアウトライン解析のサンプル
	.model small
	.code
start:
	mov ax, 1
	call func1
loop1:	dec ax
	jnz loop1

func1	proc near
	push bp
	ret
func1	endp

func2 PROC FAR
inner_label:
	ret
func2 ENDP

; label_in_comment:
data1	db 0
end start
