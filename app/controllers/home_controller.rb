# Landing page for every role: who you are, what the matrix lets you do, and the
# teams and people you can see.
class HomeController < ApplicationController
  def show
    authorize :board, :view_own?
    @teams = policy_scope(Team).order(:name)
    @my_row = Board::Snapshot.rows_for([ current_user ]).first if current_user.agent?
    @people = policy_scope(User).includes(:team).order(:last_name, :first_name)
  end
end
