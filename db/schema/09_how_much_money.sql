create or replace view how_much_money as
with recursive bounds as (
  select date_trunc('month', min(order_timestamp)) min_m,
         date_trunc('month', max(order_timestamp)) max_m
    from "order"
   where status = 'доставлен'
),
months as (
  select min_m m, max_m
    from bounds
   where min_m is not null
  union all
  select (m + interval '1 month'), max_m
    from months
   where (m + interval '1 month') <= max_m
),
order_monthly as (
  select date_trunc('month', order_timestamp) m,
         coalesce(sum(order_amount), 0) sum_no_commission,
         coalesce(sum(total_amount), 0) sum_with_commission
    from "order"
   where status = 'доставлен'
   group by date_trunc('month', order_timestamp)
),
pay_monthly as (
  select make_date(year, month, 1) m,
         coalesce(sum(amount), 0) courier_pay
    from courier_pay
   group by year, month
),
monthly_calc as (
  select to_char(m.m, 'yyyy-mm') year_month,
         coalesce(om.sum_no_commission, 0) sum_no_commission,
         coalesce(om.sum_with_commission, 0) sum_with_commission,
         (coalesce(om.sum_with_commission, 0) - coalesce(om.sum_no_commission, 0)) commission,
         coalesce(pm.courier_pay, 0) courier_pay,
         m.m
    from months m
      left join order_monthly om on m.m = om.m
      left join pay_monthly pm on m.m = pm.m
)
select year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       lag(commission) over (order by m) prev_commission,
       (commission - lag(commission) over (order by m)) commission_diff,
       courier_pay,
       (commission - courier_pay) net_profit
  from monthly_calc;
