class IssueSprintsController < ApplicationController
  unloadable
  before_filter :find_project, :authorize

  helper SprintsHelper
  helper CustomFieldsHelper  

  
  # Add a new issue
  # The new issue will be created from an existing one if copy_from parameter is given
  def new
    @issue = Issue.new
    @issue.copy_from(params[:copy_from]) if params[:copy_from]
    @issue.project = @project
    @issue.user_story_id = params[:user_story_id] unless params[:user_story_id].blank? 
    # Tracker must be set before custom field values
    @issue.tracker ||= @project.trackers.find((params[:issue] && params[:issue][:tracker_id]) || params[:tracker_id] || :first)
    if @issue.tracker.nil?
      render_error l(:error_no_tracker_in_project)
      return
    end
    if params[:issue].is_a?(Hash)
      @issue.attributes = params[:issue]
      @issue.watcher_user_ids = params[:issue]['watcher_user_ids'] if User.current.allowed_to?(:add_issue_watchers, @project)
    end
    @issue.author = User.current

    default_status = IssueStatus.default
    unless default_status
      render_error l(:error_no_default_issue_status)
      return
    end
    @issue.status = default_status
    @allowed_statuses = ([default_status] + default_status.find_new_statuses_allowed_to(User.current.roles_for_project(@project), @issue.tracker)).uniq

    if request.get? || request.post? && !params[:reload].blank?
      @issue.start_date ||= Date.today
      @priorities = IssuePriority.all
      render :partial => "issue_sprints/new"
    else
      requested_status = IssueStatus.find_by_id(params[:issue][:status_id])
      # Check that the user is allowed to apply the requested status
      @issue.status = (@allowed_statuses.include? requested_status) ? requested_status : default_status
      @issue.fixed_version_id = @issue.user_story.version_id
      if @issue.save
        status = done_ratio_to_status(@issue)
        attach_files(@issue, params[:attachments])
        call_hook(:controller_issues_new_after_save, { :params => params, :issue => @issue})
        render :update do |p|
          p.insert_html :bottom, "tasks_#{status}_us_#{@issue.user_story_id}", :partial => "shared/task_view", :locals => {:task => @issue}
        end
        return
      end
    end
  end

  def status_change
    issue = Issue.find(params[:task_id])

    if User.current.allowed_to?(:edit_issues, @project)
      journal = issue.init_journal(User.current, nil)

      if !issue.nil? && (done_ratio_to_status(issue) != params[:status_id] || issue.user_story_id != params[:user_story_id])
        if done_ratio_to_status(issue) != params[:status_id]
          issue.done_ratio = status_to_done_ratio(params[:status_id])
        end
        issue.user_story_id = params[:user_story_id]
        issue.author = User.current
      end

      if issue.save
        render :update do |p|
          p.insert_html :bottom, "tasks_#{params[:status_id]}_us_#{issue.user_story_id}", :partial => "shared/task_view", :locals => {:task => issue}
        end
      end
    end
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
    rescue ActiveRecord::RecordNotFound
      render_404
  end

  def done_ratio_to_status(issue)
    case issue.done_ratio
    when 0
      "1"
    when 100
      "3"
    else
      "2"
    end
  end

  def status_to_done_ratio(status)
    case status
    when "1"
      0
    when "3"
      100
    else
      50
    end
  end

end