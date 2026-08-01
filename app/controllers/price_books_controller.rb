# PG11 — admin CRUD for price books. Entries (product + currency + unit price)
# are edited inline via nested attributes; blank slots let admins add rows.
class PriceBooksController < ApplicationController
  require_feature "crm"
  before_action :set_book, only: %i[edit update destroy]

  BLANK_ENTRY_SLOTS = 3

  def index
    authorize PriceBook
    @books = policy_scope(PriceBook).order(is_default: :desc, name: :asc).includes(:price_book_entries)
  end

  def new
    @book = PriceBook.new
    BLANK_ENTRY_SLOTS.times { @book.price_book_entries.build }
    authorize @book
  end

  def create
    @book = PriceBook.new(book_params)
    authorize @book
    if @book.save
      redirect_to price_books_path, notice: t(".created")
    else
      pad_entries(@book)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @book
    pad_entries(@book)
  end

  def update
    authorize @book
    if @book.update(book_params)
      redirect_to price_books_path, notice: t(".updated")
    else
      pad_entries(@book)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @book
    if @book.is_default?
      redirect_to price_books_path, alert: t(".default_undeletable"), status: :see_other
    else
      @book.destroy
      redirect_to price_books_path, notice: t(".deleted"), status: :see_other
    end
  end

  private

  def set_book
    @book = PriceBook.find(params[:id])
  end

  def pad_entries(book)
    blanks = BLANK_ENTRY_SLOTS - book.price_book_entries.reject(&:persisted?).size
    blanks.clamp(0..).times { book.price_book_entries.build }
  end

  def book_params
    params.require(:price_book).permit(
      :name, :active,
      price_book_entries_attributes: %i[id product_id currency unit_price _destroy]
    )
  end
end
