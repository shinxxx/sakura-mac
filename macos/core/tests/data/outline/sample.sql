-- PL/SQL のアウトライン解析のサンプル
CREATE OR REPLACE PACKAGE pkg_sample IS
	FUNCTION get_count RETURN NUMBER;
	PROCEDURE do_work(p_id IN NUMBER);
END pkg_sample;
/

CREATE OR REPLACE PACKAGE BODY pkg_sample IS
	FUNCTION get_count RETURN NUMBER IS
	BEGIN
		RETURN 1;
	END get_count;

	PROCEDURE do_work(p_id IN NUMBER) IS
		v_name VARCHAR2(10);
	BEGIN
		NULL;
	END do_work;
END pkg_sample;
/

CREATE OR REPLACE PROCEDURE standalone_proc AS
BEGIN
	NULL;
END;
/

CREATE OR REPLACE FUNCTION standalone_func(a NUMBER) RETURN NUMBER AS
BEGIN
	RETURN a;
END;
/
