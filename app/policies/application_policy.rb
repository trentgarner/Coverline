# Base policy: everything is denied unless a subclass allows it. The permission
# matrix (plan section 2) is implemented in the subclasses below.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    raise Pundit::NotAuthorizedError, "You must be signed in." unless user
    @user = user
    @record = record
  end

  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      raise Pundit::NotAuthorizedError, "You must be signed in." unless user
      @user = user
      @scope = scope
    end

    def resolve = scope.none
  end
end
