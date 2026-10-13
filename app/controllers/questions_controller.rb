class QuestionsController < ApplicationController
  include EventScoped
  before_action { authorize! :edit }
  before_action :set_question, except: %i[index new create]

  def index
    @questions = @event.questions.includes(:rsvp_answers).to_a
  end

  def new
    @question = @event.questions.new(kind: params[:kind].presence_in(EventQuestion::KINDS.keys) || "short_text")
  end

  def create
    @question = @event.questions.new(question_params)
    if @question.save
      redirect_to event_questions_path(@event), notice: "Question added to the RSVP form."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @question.update(question_params)
      redirect_to event_questions_path(@event), notice: "Question updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @question.destroy!
    redirect_to event_questions_path(@event), notice: "Question removed (along with its answers).", status: :see_other
  end

  def move
    questions = @event.questions.to_a
    index = questions.index(@question)
    swap_with = params[:direction] == "up" ? index - 1 : index + 1
    if swap_with.between?(0, questions.size - 1)
      questions[index], questions[swap_with] = questions[swap_with], questions[index]
      EventQuestion.transaction { questions.each_with_index { |q, i| q.update_column(:position, i + 1) } }
    end
    redirect_to event_questions_path(@event), status: :see_other
  end

  private
    def set_question
      @question = @event.questions.find(params[:id])
    end

    def question_params
      params.expect(question: %i[prompt kind options_text required applies_to])
    end
end
