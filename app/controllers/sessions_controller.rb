class SessionsController < ApplicationController
  include TokenAuthentication

  def new
    return redirect_to("/dashboard") if find_user_from_cookie

    render layout: false
  end
end
