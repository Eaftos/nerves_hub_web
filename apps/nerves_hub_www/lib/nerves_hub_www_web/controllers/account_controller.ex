defmodule NervesHubWWWWeb.AccountController do
  use NervesHubWWWWeb, :controller

  alias Ecto.Changeset
  alias NervesHubWebCore.Accounts
  alias NervesHubWebCore.Accounts.User
  alias NervesHubWebCore.Accounts.Email
  alias NervesHubWebCore.Mailer

  plug(NervesHubWWWWeb.Plugs.AllowUninvitedSignups when action in [:new, :create])

  def new(conn, _params) do
    render(conn, "new.html", changeset: %Changeset{data: %User{}})
  end

  @doc """
  This action is triggered by a "Create Account" UI request. There is no
  organization involved save the one created for the user.
  """
  def create(conn, %{"user" => user_params}) do
    user_params
    |> whitelist([:password, :username, :email])
    |> Accounts.create_user()
    |> case do
      {:ok, _new_user} ->
        redirect(conn, to: "/login")

      {:error, changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def edit(conn, _params) do
    conn
    |> render(
      "edit.html",
      changeset: %Changeset{data: conn.assigns.user}
    )
  end

  def update(conn, params) do
    cleaned =
      params["user"]
      |> whitelist([:current_password, :password, :username, :email, :orgs])

    conn.assigns.user
    |> Accounts.update_user(cleaned)
    |> case do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Account updated")
        |> redirect(to: Routes.account_path(conn, :edit, user.username))

      {:error, changeset} ->
        conn
        |> render("edit.html", changeset: changeset)
    end
  end

  def invite(conn, %{"token" => token} = _) do
    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      render(
        conn,
        "invite.html",
        changeset: %Changeset{data: invite},
        org: org,
        token: token
      )
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid or expired invite")
        |> redirect(to: "/")
    end
  end

  def accept_invite(conn, %{"user" => user_params, "token" => token} = _) do
    clean_params = whitelist(user_params, [:password, :username])

    with {:ok, invite} <- Accounts.get_valid_invite(token),
         {:ok, org} <- Accounts.get_org(invite.org_id) do
      with {:ok, {:ok, new_org_user}} <-
             Accounts.create_user_from_invite(invite, org, clean_params) do
        # Now let everyone in the organization - except the new guy -
        # know about this new user.
        instigator = conn.assigns.user.username

        email =
          Email.tell_org_user_added(
            org,
            Accounts.get_org_users(org),
            instigator,
            new_org_user.user
          )

        email
        |> Mailer.deliver_later()

        conn
        |> put_flash(:info, "Account successfully created, login below")
        |> redirect(to: "/login")
      else
        {:error, %Changeset{} = changeset} ->
          render(
            conn,
            "invite.html",
            changeset: changeset,
            org: org,
            token: token
          )
      end
    else
      {:error, :invite_not_found} ->
        conn
        |> put_flash(:error, "Invalid or expired invite")
        |> redirect(to: "/")

      {:error, :org_not_found} ->
        conn
        |> put_flash(:error, "Invalid org")
        |> redirect(to: "/")
    end
  end
end
