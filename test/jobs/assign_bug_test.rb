require 'test_helper'

class AssignBugTest < ActiveJob::TestCase
  test "existing bug assignment" do
    occurrence = occurrences(:prod_normal_unassigned)
    assert_no_difference 'Bug.count' do
      AssignBug.perform_now(occurrence)
    end
    assert_equal bugs(:prod_normal), occurrence.bug
  end

  test "new bug assignment" do
    occurrence = occurrences(:prod_new_unassigned)
    assert_difference 'Bug.count', 1 do
      AssignBug.perform_now(occurrence)
    end
    bug = occurrence.bug
    assert_equal 'created', bug.events.first!.name
    assert_equal occurrence, bug.primary_occurrence
  end
end
