DROP TRIGGER IF EXISTS trg_customer_sanitized_ins ON public.customer;
DROP TRIGGER IF EXISTS trg_customer_sanitized_upd ON public.customer;

CREATE TRIGGER trg_customer_sanitized_ins
AFTER INSERT ON public.customer
FOR EACH ROW EXECUTE FUNCTION sanitized.write_customer_sanitized();

CREATE TRIGGER trg_customer_sanitized_upd
AFTER UPDATE ON public.customer
FOR EACH ROW EXECUTE FUNCTION sanitized.write_customer_sanitized();
