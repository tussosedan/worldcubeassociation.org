# frozen_string_literal: true

module ResultsValidators
  class ScramblesValidator < GenericValidator
    MISSING_SCRAMBLES_FOR_ROUND_ERROR = "[%{round_id}] Missing scrambles. Use the workbook assistant to add the correct scrambles to the round."
    MISSING_SCRAMBLES_FOR_COMPETITION_ERROR = "Missing scrambles for the competition. Use the workbook assistant to add scrambles."
    UNEXPECTED_SCRAMBLES_FOR_ROUND_ERROR = "[%{round_id}] Too many scrambles. Use the workbook assistant to uncheck the unused scrambles."
    MISSING_SCRAMBLES_FOR_GROUP_ERROR = "[%{round_id}] Group %{group_id}: missing scrambles, detected only %{actual} instead of %{expected}."

    @@desc = "This validator checks that all results have matching scrambles, and if possible, checks that the scrambles have the correct number of attempts compared to the expected round format."

    def validate(competition_ids: [], model: Result, results: nil)
      reset_state
      # Get all results if not provided
      results ||= model.sorted_for_competitions(competition_ids)

      associations = {
        events: [],
        competition_events: {
          rounds: [:competition_event],
        },
      }

      results_by_competition_id = results.group_by(&:competitionId)

      scrambles = Scramble.where(competitionId: results_by_competition_id.keys).group_by(&:competitionId)

      competitions = Hash[
        Competition.includes(associations).where(id: results_by_competition_id.keys).map do |c|
          [c.id, c]
        end
      ]

      results_by_competition_id.each do |competition_id, results_for_comp|
        # Get actual round ids from results
        rounds_ids = results_for_comp.map { |r| "#{r.eventId}-#{r.roundTypeId}" }.uniq

        unless scrambles[competition_id]&.any?
          @errors << ValidationError.new(:scrambles, competition_id,
                                         MISSING_SCRAMBLES_FOR_COMPETITION_ERROR,
                                         competition_id: competition_id)
          next
        end

        # Group scramble by round_id
        scrambles_by_round_id = scrambles[competition_id].group_by { |s| "#{s.eventId}-#{s.roundTypeId}" }
        detected_scrambles_rounds_ids = scrambles_by_round_id.keys
        (rounds_ids - detected_scrambles_rounds_ids).each do |round_id|
          @errors << ValidationError.new(:scrambles, competition_id,
                                         MISSING_SCRAMBLES_FOR_ROUND_ERROR,
                                         round_id: round_id)
        end

        (detected_scrambles_rounds_ids - rounds_ids).each do |round_id|
          @errors << ValidationError.new(:scrambles, competition_id,
                                         UNEXPECTED_SCRAMBLES_FOR_ROUND_ERROR,
                                         round_id: round_id)
        end

        rounds_info_by_ids = get_rounds_info(competitions[competition_id], rounds_ids)

        # For existing rounds and scrambles matching expected rounds in the WCA website,
        # check that the number of scrambles match at least the number of expected scrambles.
        (detected_scrambles_rounds_ids & rounds_info_by_ids.keys).each do |round_id|
          format = rounds_info_by_ids[round_id].format
          expected_number_of_scrambles = format.expected_solve_count
          scrambles_by_group_id = scrambles_by_round_id[round_id].group_by(&:groupId)
          scrambles_by_group_id.each do |group_id, scrambles_for_group|
            # filter out extra scrambles
            actual_number_of_scrambles = scrambles_for_group.reject(&:isExtra).size
            if actual_number_of_scrambles < expected_number_of_scrambles
              @errors << ValidationError.new(:scrambles, competition_id,
                                             MISSING_SCRAMBLES_FOR_GROUP_ERROR,
                                             round_id: round_id, group_id: group_id,
                                             actual: actual_number_of_scrambles,
                                             expected: expected_number_of_scrambles)
            end
          end
        end
      end
      self
    end
  end
end