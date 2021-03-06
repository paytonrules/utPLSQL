create or replace type body ut_run as
  /*
  utPLSQL - Version X.X.X.X
  Copyright 2016 - 2017 utPLSQL Project

  Licensed under the Apache License, Version 2.0 (the "License"):
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
  */

  constructor function ut_run(
    self in out nocopy ut_run, a_items ut_suite_items, a_run_paths ut_varchar2_list := null,
    a_coverage_options ut_coverage_options := null, a_test_file_mappings ut_file_mappings := null
  ) return self as result is
    l_run_schemes ut_varchar2_list;
  begin
    self.run_paths := a_run_paths;
    self.self_type := $$plsql_unit;
    self.items := a_items;
    self.results_count := ut_results_counter();
    self.coverage_options := a_coverage_options;
    self.test_file_mappings := coalesce(a_test_file_mappings, ut_file_mappings());
    if self.coverage_options is not null then
      l_run_schemes := get_run_schemes();
      coverage_options.schema_names := l_run_schemes;
      if coverage_options.exclude_objects is not null then
        coverage_options.exclude_objects :=
          coverage_options.exclude_objects
          multiset union all
          ut_suite_manager.get_schema_ut_packages(l_run_schemes);
      else
        coverage_options.exclude_objects := ut_suite_manager.get_schema_ut_packages(l_run_schemes);
      end if;
    end if;
    return;
  end;

  overriding member function do_execute(self in out nocopy ut_run, a_listener in out nocopy ut_event_listener_base) return boolean is
    l_completed_without_errors boolean;
  begin
    ut_utils.debug_log('ut_run.execute');

    a_listener.fire_before_event(ut_utils.gc_run, self);

    self.start_time := current_timestamp;

    -- clear anything that might stay in the session's cache
    ut_expectation_processor.clear_expectations;

    for i in 1 .. self.items.count loop
      l_completed_without_errors := self.items(i).do_execute(a_listener);
    end loop;

    self.calc_execution_result();

    self.end_time := current_timestamp;

    a_listener.fire_after_event(ut_utils.gc_run, self);

    return l_completed_without_errors;
  end;

  overriding member procedure calc_execution_result(self in out nocopy ut_run) is
    l_result integer(1);
  begin
    if self.items is not null and self.items.count > 0 then
      for i in 1 .. self.items.count loop
        self.results_count.sum_counter_values( self.items(i).results_count );
      end loop;
      l_result := self.results_count.result_status();
    else
      --if suite is empty then it's successful (no errors)
      l_result := ut_utils.tr_success;
    end if;

    self.result := l_result;
  end;

  overriding member procedure mark_as_errored(self in out nocopy ut_run, a_listener in out nocopy ut_event_listener_base, a_error_stack_trace varchar2) is
  begin
    ut_utils.debug_log('ut_run.fail');

    a_listener.fire_before_event(ut_utils.gc_run, self);
    self.start_time := current_timestamp;

    for i in 1 .. self.items.count loop
      self.items(i).mark_as_errored(a_listener, a_error_stack_trace);
    end loop;

    self.calc_execution_result();
    self.end_time := self.start_time;

    a_listener.fire_after_event(ut_utils.gc_run, self);
  end;

  member function get_run_schemes return ut_varchar2_list is
    l_schema          varchar2(128);
    c_current_schema  constant varchar2(128) := sys_context('USERENV','CURRENT_SCHEMA');
    l_path            varchar2(32767);
    l_schemes         ut_varchar2_list;
  begin
    if run_paths is not null then
      l_schemes := ut_varchar2_list();
      for i in 1 .. self.run_paths.count loop
        l_path := self.run_paths(i);
        if regexp_like(l_path, '^(\w+)?:') then
          l_schema := regexp_substr(l_path, '^(\w+)?:',subexpression => 1);
          if l_schema is not null then
            l_schema := sys.dbms_assert.schema_name(upper(l_schema));
          else
            l_schema := c_current_schema;
          end if;
        else
          begin
            l_schema := sys.dbms_assert.schema_name(upper(regexp_substr(l_path, '^\w+')));
          exception
            when sys.dbms_assert.invalid_schema_name then
              l_schema := c_current_schema;
          end;

        end if;
        l_schemes.extend;
        l_schemes(l_schemes.last) := l_schema;
      end loop;
    else
      l_schemes := ut_varchar2_list(c_current_schema);
    end if;
    return l_schemes;

  end;

  overriding member function get_error_stack_traces return ut_varchar2_list is
  begin
    return ut_varchar2_list();
  end;

  overriding member function get_serveroutputs return clob is
  begin
    return null;
  end;


end;
/
