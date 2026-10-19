# frozen_string_literal: true

module CursorPagination
  # Positions a scope on a cursor. When the sort runs in a single direction, a single
  # row-value comparison bounds the page and an index on the tuple serves it (read
  # backward for an ascending sort on a descending index). When it mixes directions, the
  # bound is the expansion `a < x OR (a = x AND b < y) OR (a = x AND b = y AND c > z)`,
  # that row values cannot express.
  module Keyset
    # Must be the last scope operation of a query: `reorder` drops any ordering applied
    # before it, and a later `order` would be appended after the tuple.
    def self.apply(scope, cursor)
      if scope.table_name != cursor.table
        raise ArgumentError, "cursor minted for #{cursor.table} applied to #{scope.table_name}"
      end

      scope = scope.where(*bound(scope, cursor)) unless cursor.direction == :first

      # One extra row tells whether the list continues in the direction being paged.
      scope.reorder(order(cursor)).limit(cursor.limit + 1)
    end

    # The order the page is read in. Paging backward walks towards the start of the list,
    # so the rows closest to the anchor come first; `Page` restores the list order.
    def self.order(cursor)
      cursor.backward? ? reversed(cursor.sort) : cursor.sort
    end

    def self.bound(scope, cursor)
      sort = cursor.sort
      columns = sort.keys.map { |column| "#{scope.quoted_table_name}.#{scope.connection.quote_column_name(column)}" }
      operators = sort.values.map { |direction| operator(direction, cursor.direction) }

      if CursorPagination.uniform?(sort)
        ["(#{columns.join(", ")}) #{operators.first} (#{(["?"] * columns.size).join(", ")})", *cursor.key]
      else
        expansion(columns, operators, cursor.key)
      end
    end
    private_class_method :bound

    # The leading column is also bounded on its own, which the expansion implies: it gives
    # an index on the tuple a start, where the OR alone would be a filter over the list.
    def self.expansion(columns, operators, key)
      binds = key.each_with_index.to_h { |value, index| [:"k#{index}", value] }
      branches = columns.each_index.map do |last|
        ties = columns.first(last).each_with_index.map { |column, index| "#{column} = :k#{index}" }
        "(#{[*ties, "#{columns[last]} #{operators[last]} :k#{last}"].join(" AND ")})"
      end

      ["#{columns.first} #{operators.first}= :k0 AND (#{branches.join(" OR ")})", binds]
    end
    private_class_method :expansion

    # The rows past the anchor, in the direction being paged: lower values when walking
    # forward a descending sort, higher ones when walking it backward, and the other way
    # around for an ascending sort.
    def self.operator(direction, paging)
      ((direction == :desc) == (paging == :forward)) ? "<" : ">"
    end
    private_class_method :operator

    def self.reversed(sort)
      sort.transform_values { (it == :desc) ? :asc : :desc }
    end
    private_class_method :reversed
  end
end
