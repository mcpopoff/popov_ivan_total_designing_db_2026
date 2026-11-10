create or replace procedure courier_salary()
as $$
declare
  cur_year$i int := extract(year from current_date)::int;
  cur_month$i int := extract(month from current_date)::int;
  c_rec record;
  deliv_cnt$i int;
  comm_sum$n numeric;
  curr_coef$n numeric;
  pay_amt$n numeric;
  new_coef$n numeric;
begin
  for c_rec in
    select courier_id,
           coefficient,
           status
      from courier
  loop
    select coefficient_used
      into curr_coef$n
      from courier_pay
     where year = cur_year$i
       and month = cur_month$i
       and courier_id = c_rec.courier_id;

    if curr_coef$n is null then
      curr_coef$n := c_rec.coefficient;
    end if;

    select coalesce(count(*), 0),
           coalesce(sum(commission), 0)
      into deliv_cnt$i,
           comm_sum$n
      from "order"
     where courier_id = c_rec.courier_id
       and status = 'доставлен'
       and extract(year from order_timestamp) = cur_year$i
       and extract(month from order_timestamp) = cur_month$i;

    pay_amt$n := round(comm_sum$n * curr_coef$n, 2);

    if exists (
      select 1
        from courier_pay
       where year = cur_year$i
         and month = cur_month$i
         and courier_id = c_rec.courier_id
    ) then
      update courier_pay
         set amount = pay_amt$n,
             coefficient_used = curr_coef$n
       where year = cur_year$i
         and month = cur_month$i
         and courier_id = c_rec.courier_id;
    else
      insert into courier_pay (year, month, courier_id, amount, coefficient_used)
      values (cur_year$i, cur_month$i, c_rec.courier_id, pay_amt$n, curr_coef$n);
    end if;

    if c_rec.status != 'уволен' then
      if deliv_cnt$i <= 150 then
        new_coef$n := 0.1;
      elsif deliv_cnt$i <= 250 then
        new_coef$n := 0.2;
      elsif deliv_cnt$i <= 500 then
        new_coef$n := 0.3;
      else
        new_coef$n := 0.5;
      end if;

      update courier
         set coefficient = new_coef$n
       where courier_id = c_rec.courier_id;
    end if;
  end loop;
end;
$$ language plpgsql;
