Feature: ecctool trigger-repair

  Scenario: Trigger repair for keyspace test2 and table table2
    Given we have access to ecctool
    When we trigger repair for keyspace test2 and table table2
    Then the trigger repair output should contain a valid header
    And the trigger repair output should contain a row for test2.table2
    And the trigger repair output should not contain more rows
