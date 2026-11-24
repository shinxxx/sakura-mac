Attribute VB_Name = "Sample"
' Visual Basic のアウトライン解析のサンプル
Option Explicit

Public Const MAX_COUNT As Integer = 10
Private Const MIN_COUNT = 0

Public Enum Colors
	Red
	Green
End Enum

Private Type Point
	X As Long
	Y As Long
End Type

Public Event Changed(ByVal Value As Long)

Private Declare Function GetTickCount Lib "kernel32" () As Long
Public Declare Sub Sleep Lib "kernel32" (ByVal ms As Long)

Public Function Add(a As Integer, b As Integer) As Integer
	Add = a + b
End Function

Private Sub Reset()
End Sub

Friend Function Helper() As String
End Function

Static Sub Counter()
End Sub

Public Static Function StaticFunc() As Long
End Function

Property Get Value() As Long
End Property

Public Property Let Value(ByVal v As Long)
End Property

Private Property Set Target(ByVal o As Object)
End Property

Sub NoModifier()
End Sub
