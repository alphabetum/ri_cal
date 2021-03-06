module RiCal
  #- ©2009 Rick DeNatale
  #- All rights reserved. Refer to the file README.txt for the license
  #
  # OccurrenceEnumerator provides common methods for CalendarComponents that support recurrence
  # i.e. Event, Journal, Todo, and TimezonePeriod
  module OccurrenceEnumerator
    
    include Enumerable

    def default_duration # :nodoc:    
      dtend && dtstart.to_ri_cal_date_time_value.duration_until(dtend)
    end

    def default_start_time # :nodoc:
      dtstart && dtstart.to_ri_cal_date_time_value
    end

    class EmptyRulesEnumerator # :nodoc:
      def self.next_occurrence
        nil
      end
    end
    
    # OccurrenceMerger takes multiple recurrence rules and enumerates the combination in sequence. 
    class OccurrenceMerger # :nodoc:
      def self.for(component, rules)
        if rules.nil? || rules.empty?
          EmptyRulesEnumerator
        elsif rules.length == 1
          rules.first.enumerator(component)
        else
          new(component, rules)
        end
      end
      
      attr_accessor :enumerators, :nexts
      
      def initialize(component, rules)
        self.enumerators = rules.map {|rrule| rrule.enumerator(component)}
        @bounded = enumerators.all? {|enumerator| enumerator.bounded?}
        self.nexts = @enumerators.map {|enumerator| enumerator.next_occurrence}
      end
      
      # return the earliest of each of the enumerators next occurrences
      def next_occurrence        
        result = nexts.compact.sort.first
        if result
          nexts.each_with_index { |datetimevalue, i| @nexts[i] = @enumerators[i].next_occurrence if result == datetimevalue }
        end
        result
      end
      
      def bounded?
        @bounded
      end
    end
    
    # EnumerationInstance holds the values needed during the enumeration of occurrences for a component.
    class EnumerationInstance # :nodoc:
      include Enumerable
      
      def initialize(component, options = {})
        @component = component
        @start = options[:starting]
        @cutoff = options[:before]
        @count = options[:count]
        @rrules = OccurrenceMerger.for(@component, [@component.rrule_property, @component.rdate_property].flatten.compact)
        @exrules = OccurrenceMerger.for(@component, [@component.exrule_property, @component.exdate_property].flatten.compact)
      end
      
      # return the next exclusion which starts at the same time or after the start time of the occurrence
      # return nil if this exhausts the exclusion rules
      def exclusion_for(occurrence)
        while (@next_exclusion && @next_exclusion[:start] < occurrence[:start])
          @next_exclusion = @exrules.next_occurrence
        end
        @next_exclusion
      end

      # TODO: Need to research this, I beleive that this should also take the end time into account,
      #       but I need to research
      def exclusion_match?(occurrence, exclusion)
        exclusion && occurrence[:start] == occurrence[:start]
      end
      
      def exclude?(occurrence)
        exclusion_match?(occurrence, exclusion_for(occurrence))
      end
      
      # yield each occurrence to a block
      # some components may be open-ended, e.g. have no COUNT or DTEND 
      def each
        occurrence = @rrules.next_occurrence
        yielded = 0
        @next_exclusion = @exrules.next_occurrence
        while (occurrence)
          if (@cutoff && occurrence[:start] >= @cutoff) || (@count && yielded >= @count)
            occurrence = nil
          else
            unless exclude?(occurrence)
              yielded += 1
             yield @component.recurrence(occurrence)
            end
            occurrence = @rrules.next_occurrence
          end
        end
      end
      
      def bounded?
        @rrules.bounded? || @count || @cutoff
      end
      
      def to_a
        raise ArgumentError.new("This component is unbounded, cannot produce an array of occurrences!") unless bounded?
        super
      end
      
      alias_method :entries, :to_a
    end
    
    # return an array of occurrences according to the options parameter.  If a component is not bounded, and
    # the number of occurrences to be returned is not constrained by either the :before, or :count options
    # an ArgumentError will be raised.
    #
    # The components returned will be the same type as the receiver, but will have any recurrence properties
    # (rrule, rdate, exrule, exdate) removed since they are single occurrences, and will have the recurrence-id
    # property set to the occurrences dtstart value. (see RFC 2445 sec 4.8.4.4 pp 107-109)
    #
    # parameter options:
    # * :starting:: a Date, Time, or DateTime, no occurrences starting before this argument will be returned
    # * :before:: a Date, Time, or DateTime, no occurrences starting on or after this argument will be returned. 
    # * :count:: an integer which limits the number of occurrences returned.
    def occurrences(options={})
      EnumerationInstance.new(self, options).to_a    
    end
    
    # execute the block for each occurrence
    def each(&block) # :yields: Component
      EnumerationInstance.new(self).each(&block)
    end
    
    # A predicate which determines whether the component has a bounded set of occurrences
    def bounded?
      EnumerationInstance.new(self).bounded?
    end
    #
    def set_occurrence_properties!(occurrence) # :nodoc:
      occurrence_end = occurrence[:end]
      occurrence_start = occurrence[:start]
      @rrule_property = nil
      @exrule_property = nil
      @rdate_property = nil
      @exdate_property = nil
      @recurrence_id_property = occurrence_start
      @dtstart_property = occurrence_start
      if occurrence_end
        @dtend_property = occurrence_end
      else
        if dtend
          my_duration = @dtend_property - @dtstart_property
          @dtend_property = occurrence_start + my_duration
        end
      end
      self      
    end
    
    def recurrence(occurrence) # :nodoc:
      result = self.dup.set_occurrence_properties!(occurrence)
    end
  end
end