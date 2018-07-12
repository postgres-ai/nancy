create table t1 as
  select i as id, random() val
  from generate_series(1, 1000000) _(i);

alter table t1 add primary key (id);
