class Bug < ApplicationRecord
  belongs_to :primary_occurrence, class_name: 'Occurrence'
  has_many :events
  has_many :occurrences
  has_many :issues

  belongs_to :latest_event, class_name: 'Event', optional: true

  scope :in_occurrence_order, ->{ order('last_occurred_at DESC') }
  scope :with_occurrence_includes, ->{ includes(:primary_occurrence => :environment) }
  scope :with_issue_includes, ->{ includes(:issues) }

  scope :with_occurrence_in_environment, ->(environment_ids) {
    where(Occurrence
            .where("occurrences.bug_id = bugs.id")
            .where(environment_id: environment_ids).exists)
  }
  scope :search, ->(query){ distinct.joins(:occurrences).merge(Occurrence.where("occurrences.message @@ ?", query)) }

  # closed and open rely on latest_even_name from the bug_with_latest_details view
  scope :closed, ->{ where("latest_event_name =?", "closed") }
  scope :open, ->{ where.not("latest_event_name =?", "closed") }

  scope :not_newer_than_bug, ->(bug_id) { where('last_occurred_at <= (SELECT last_occurred_at FROM bug_with_latest_details b2 WHERE b2.id = ?)', bug_id) }

  def self.with_latest_details
    from('bug_with_latest_details AS bugs')
  end
end
