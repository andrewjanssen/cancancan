require 'spec_helper'

if defined? CanCan::ModelAdapters::ActiveRecordAdapter

  describe CanCan::ModelAdapters::ActiveRecordAdapter do
    before :each do
      ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
      ActiveRecord::Migration.verbose = false
      ActiveRecord::Schema.define do
        create_table(:categories) do |t|
          t.string :name
          t.boolean :visible
          t.timestamps null: false
        end

        create_table(:projects) do |t|
          t.string :name
          t.timestamps null: false
        end

        create_table(:articles) do |t|
          t.string :name
          t.timestamps null: false
          t.boolean :published
          t.boolean :secret
          t.integer :priority
          t.integer :category_id
          t.integer :user_id
        end

        create_table(:comments) do |t|
          t.boolean :spam
          t.integer :article_id
          t.timestamps null: false
        end

        create_table(:legacy_mentions) do |t|
          t.integer :user_id
          t.integer :article_id
          t.timestamps null: false
        end

        create_table(:users) do |t|
          t.string :name
          t.timestamps null: false
        end
      end

      class Project < ActiveRecord::Base
      end

      class Category < ActiveRecord::Base
        has_many :articles
      end

      class Article < ActiveRecord::Base
        belongs_to :category
        has_many :comments
        has_many :mentions
        has_many :mentioned_users, through: :mentions, source: :user
        belongs_to :user
      end

      class Mention < ActiveRecord::Base
        self.table_name = 'legacy_mentions'
        belongs_to :user
        belongs_to :article
      end

      class Comment < ActiveRecord::Base
        belongs_to :article
      end

      class User < ActiveRecord::Base
        has_many :articles
        has_many :mentions
        has_many :mentioned_articles, through: :mentions, source: :article
      end

      (@ability = double).extend(CanCan::Ability)
      @article_table = Article.table_name
      @comment_table = Comment.table_name
    end

    it 'is for only active record classes' do
      if ActiveRecord.respond_to?(:version) &&
         ActiveRecord.version > Gem::Version.new('6')
        expect(CanCan::ModelAdapters::ActiveRecord6Adapter).to_not be_for_class(Object)
        expect(CanCan::ModelAdapters::ActiveRecord6Adapter).to be_for_class(Article)
        expect(CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article))
          .to eq(CanCan::ModelAdapters::ActiveRecord6Adapter)
      elsif ActiveRecord.respond_to?(:version) &&
         ActiveRecord.version > Gem::Version.new('5')
        expect(CanCan::ModelAdapters::ActiveRecord5Adapter).to_not be_for_class(Object)
        expect(CanCan::ModelAdapters::ActiveRecord5Adapter).to be_for_class(Article)
        expect(CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article))
          .to eq(CanCan::ModelAdapters::ActiveRecord5Adapter)
      elsif ActiveRecord.respond_to?(:version) &&
            ActiveRecord.version > Gem::Version.new('4')
        expect(CanCan::ModelAdapters::ActiveRecord4Adapter).to_not be_for_class(Object)
        expect(CanCan::ModelAdapters::ActiveRecord4Adapter).to be_for_class(Article)
        expect(CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article))
          .to eq(CanCan::ModelAdapters::ActiveRecord4Adapter)
      end
    end

    it 'finds record' do
      article = Article.create!
      adapter = CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article)
      expect(adapter.find(Article, article.id)).to eq(article)
    end

    it 'does not fetch any records when no abilities are defined' do
      Article.create!
      expect(Article.accessible_by(@ability)).to be_empty
    end

    it 'fetches all articles when one can read all' do
      @ability.can :read, Article
      article = Article.create!
      expect(Article.accessible_by(@ability)).to eq([article])
    end

    it 'fetches only the articles that are published' do
      @ability.can :read, Article, published: true
      article1 = Article.create!(published: true)
      Article.create!(published: false)
      expect(Article.accessible_by(@ability)).to eq([article1])
    end

    it 'fetches any articles which are published or secret' do
      @ability.can :read, Article, published: true
      @ability.can :read, Article, secret: true
      article1 = Article.create!(published: true, secret: false)
      article2 = Article.create!(published: true, secret: true)
      article3 = Article.create!(published: false, secret: true)
      Article.create!(published: false, secret: false)
      expect(Article.accessible_by(@ability)).to eq([article1, article2, article3])
    end

    it 'fetches any articles which we are cited in' do
      user = User.create!
      cited = Article.create!
      Article.create!
      cited.mentioned_users << user
      @ability.can :read, Article, mentioned_users: { id: user.id }
      @ability.can :read, Article, mentions: { user_id: user.id }
      expect(Article.accessible_by(@ability)).to eq([cited])
    end

    it 'fetches only the articles that are published and not secret' do
      @ability.can :read, Article, published: true
      @ability.cannot :read, Article, secret: true
      article1 = Article.create!(published: true, secret: false)
      Article.create!(published: true, secret: true)
      Article.create!(published: false, secret: true)
      Article.create!(published: false, secret: false)
      expect(Article.accessible_by(@ability)).to eq([article1])
    end

    it 'only reads comments for articles which are published' do
      @ability.can :read, Comment, article: { published: true }
      comment1 = Comment.create!(article: Article.create!(published: true))
      Comment.create!(article: Article.create!(published: false))
      expect(Comment.accessible_by(@ability)).to eq([comment1])
    end

    it 'should only read articles which are published or in visible categories' do
      @ability.can :read, Article, category: { visible: true }
      @ability.can :read, Article, published: true
      article1 = Article.create!(published: true)
      Article.create!(published: false)
      article3 = Article.create!(published: false, category: Category.create!(visible: true))
      expect(Article.accessible_by(@ability)).to eq([article1, article3])
    end

    it 'should only read categories once even if they have multiple articles' do
      @ability.can :read, Category, articles: { published: true }
      @ability.can :read, Article, published: true
      category = Category.create!
      Article.create!(published: true, category: category)
      Article.create!(published: true, category: category)
      expect(Category.accessible_by(@ability)).to eq([category])
    end

    it 'only reads comments for visible categories through articles' do
      @ability.can :read, Comment, article: { category: { visible: true } }
      comment1 = Comment.create!(article: Article.create!(category: Category.create!(visible: true)))
      Comment.create!(article: Article.create!(category: Category.create!(visible: false)))
      expect(Comment.accessible_by(@ability)).to eq([comment1])
    end

    it 'allows conditions in SQL and merge with hash conditions' do
      @ability.can :read, Article, published: true
      @ability.can :read, Article, ['secret=?', true]
      article1 = Article.create!(published: true, secret: false)
      article2 = Article.create!(published: true, secret: true)
      article3 = Article.create!(published: false, secret: true)
      Article.create!(published: false, secret: false)
      expect(Article.accessible_by(@ability)).to eq([article1, article2, article3])
    end

    it 'allows a scope for conditions' do
      @ability.can :read, Article, Article.where(secret: true)
      article1 = Article.create!(secret: true)
      Article.create!(secret: false)
      expect(Article.accessible_by(@ability)).to eq([article1])
    end

    it 'fetches only associated records when using with a scope for conditions' do
      @ability.can :read, Article, Article.where(secret: true)
      category1 = Category.create!(visible: false)
      category2 = Category.create!(visible: true)
      article1 = Article.create!(secret: true, category: category1)
      Article.create!(secret: true, category: category2)
      expect(category1.articles.accessible_by(@ability)).to eq([article1])
    end

    it 'raises an exception when trying to merge scope with other conditions' do
      @ability.can :read, Article, published: true
      @ability.can :read, Article, Article.where(secret: true)
      expect(-> { Article.accessible_by(@ability) })
        .to raise_error(CanCan::Error,
                        'Unable to merge an Active Record scope with other conditions. '\
                        'Instead use a hash or SQL for read Article ability.')
    end

    it 'does not allow to fetch records when ability with just block present' do
      @ability.can :read, Article do
        false
      end
      expect(-> { Article.accessible_by(@ability) }).to raise_error(CanCan::Error)
    end

    it 'should support more than one deeply nested conditions' do
      @ability.can :read, Comment, article: {
        category: {
          name: 'foo', visible: true
        }
      }
      expect { Comment.accessible_by(@ability) }.to_not raise_error
    end

    it 'does not allow to check ability on object against SQL conditions without block' do
      @ability.can :read, Article, ['secret=?', true]
      expect(-> { @ability.can? :read, Article.new }).to raise_error(CanCan::Error)
    end

    it 'has false conditions if no abilities match' do
      expect(@ability.model_adapter(Article, :read).conditions).to eq("'t'='f'")
    end

    it 'returns false conditions for cannot clause' do
      @ability.cannot :read, Article
      expect(@ability.model_adapter(Article, :read).conditions).to eq("'t'='f'")
    end

    it 'returns SQL for single `can` definition in front of default `cannot` condition' do
      @ability.cannot :read, Article
      @ability.can :read, Article, published: false, secret: true
      expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
SELECT "articles".*
FROM "articles"
WHERE "articles"."published" = 'f' AND "articles"."secret" = 't'))
    end

    it 'returns true condition for single `can` definition in front of default `can` condition' do
      @ability.can :read, Article
      @ability.can :read, Article, published: false, secret: true
      expect(@ability.model_adapter(Article, :read).conditions).to eq({})
      expect(@ability.model_adapter(Article, :read)).to generate_sql(%(SELECT "articles".* FROM "articles"))
    end

    it 'returns `false condition` for single `cannot` definition in front of default `cannot` condition' do
      @ability.cannot :read, Article
      @ability.cannot :read, Article, published: false, secret: true
      expect(@ability.model_adapter(Article, :read).conditions).to eq("'t'='f'")
    end

    it 'returns `not (sql)` for single `cannot` definition in front of default `can` condition' do
      @ability.can :read, Article
      @ability.cannot :read, Article, published: false, secret: true
      expect(@ability.model_adapter(Article, :read).conditions)
        .to orderlessly_match(%["not (#{@article_table}"."published" = 'f' AND "#{@article_table}"."secret" = 't')])
    end

    it 'returns appropriate sql conditions in complex case' do
      @ability.can :read, Article
      @ability.can :manage, Article, id: 1
      @ability.can :update, Article, published: true
      @ability.cannot :update, Article, secret: true
      expect(@ability.model_adapter(Article, :update).conditions)
        .to eq(%[not ("#{@article_table}"."secret" = 't') ] +
                 %[AND (("#{@article_table}"."published" = 't') ] +
                 %[OR ("#{@article_table}"."id" = 1))])
      expect(@ability.model_adapter(Article, :manage).conditions).to eq(id: 1)
      expect(@ability.model_adapter(Article, :read).conditions).to eq({})
      expect(@ability.model_adapter(Article, :read)).to generate_sql(%(SELECT "articles".* FROM "articles"))
    end

    it 'returns appropriate sql conditions in complex case with nested joins' do
      @ability.can :read, Comment, article: { category: { visible: true } }
      expect(@ability.model_adapter(Comment, :read).conditions).to eq(Category.table_name.to_sym => { visible: true })
    end

    it 'returns appropriate sql conditions in complex case with nested joins of different depth' do
      @ability.can :read, Comment, article: { published: true, category: { visible: true } }
      expect(@ability.model_adapter(Comment, :read).conditions)
        .to eq(Article.table_name.to_sym => { published: true }, Category.table_name.to_sym => { visible: true })
    end

    it 'does not forget conditions when calling with SQL string' do
      @ability.can :read, Article, published: true
      @ability.can :read, Article, ['secret=?', false]
      adapter = @ability.model_adapter(Article, :read)
      2.times do
        expect(adapter.conditions).to eq(%[(secret='f') OR ("#{@article_table}"."published" = 't')])
      end
    end

    it 'has nil joins if no rules' do
      expect(@ability.model_adapter(Article, :read).joins).to be_nil
    end

    it 'has nil joins if no nested hashes specified in conditions' do
      @ability.can :read, Article, published: false
      @ability.can :read, Article, secret: true
      expect(@ability.model_adapter(Article, :read).joins).to be_nil
    end

    it 'merges separate joins into a single array' do
      @ability.can :read, Article, project: { blocked: false }
      @ability.can :read, Article, company: { admin: true }
      expect(@ability.model_adapter(Article, :read).joins.inspect).to orderlessly_match(%i[company project].inspect)
    end

    it 'merges same joins into a single array' do
      @ability.can :read, Article, project: { blocked: false }
      @ability.can :read, Article, project: { admin: true }
      expect(@ability.model_adapter(Article, :read).joins).to eq([:project])
    end

    it 'merges nested and non-nested joins' do
      @ability.can :read, Article, project: { blocked: false }
      @ability.can :read, Article, project: { comments: { spam: true } }
      expect(@ability.model_adapter(Article, :read).joins).to eq([{ project: [:comments] }])
    end

    it 'merges :all conditions with other conditions' do
      user = User.create!
      article = Article.create!(user: user)
      ability = Ability.new(user)
      ability.can :manage, :all
      ability.can :manage, Article, user_id: user.id
      expect(Article.accessible_by(ability)).to eq([article])
    end

    it 'should not execute a scope when checking ability on the class' do
      relation = Article.where(secret: true)
      @ability.can :read, Article, relation do |article|
        article.secret == true
      end

      allow(relation).to receive(:count).and_raise('Unexpected scope execution.')

      expect { @ability.can? :read, Article }.not_to raise_error
    end

    context 'with namespaced models' do
      before :each do
        ActiveRecord::Schema.define do
          create_table(:table_xes) do |t|
            t.timestamps null: false
          end

          create_table(:table_zs) do |t|
            t.integer :table_x_id
            t.integer :user_id
            t.timestamps null: false
          end
        end

        module Namespace
        end

        class Namespace::TableX < ActiveRecord::Base
          has_many :table_zs
        end

        class Namespace::TableZ < ActiveRecord::Base
          belongs_to :table_x
          belongs_to :user
        end
      end

      it 'fetches all namespace::table_x when one is related by table_y' do
        user = User.create!

        ability = Ability.new(user)
        ability.can :read, Namespace::TableX, table_zs: { user_id: user.id }

        table_x = Namespace::TableX.create!
        table_x.table_zs.create(user: user)
        expect(Namespace::TableX.accessible_by(ability)).to eq([table_x])
      end
    end

    context 'when conditions are non iterable ranges' do
      before :each do
        ActiveRecord::Schema.define do
          create_table(:courses) do |t|
            t.datetime :start_at
          end
        end

        class Course < ActiveRecord::Base
        end
      end

      it 'fetches only the valid records' do
        @ability.can :read, Course, start_at: 1.day.ago..1.day.from_now
        Course.create!(start_at: 10.days.ago)
        valid_course = Course.create!(start_at: Time.now)

        expect(Course.accessible_by(@ability)).to eq([valid_course])
      end
    end

    context 'when a table references another one twice' do
      before do
        ActiveRecord::Schema.define do
          create_table(:transactions) do |t|
            t.integer :sender_id
            t.integer :receiver_id
          end
        end

        class Transaction < ActiveRecord::Base
          belongs_to :sender, class_name: 'User', foreign_key: :sender_id
          belongs_to :receiver, class_name: 'User', foreign_key: :receiver_id
        end
      end

      it 'can filter correctly on both associations' do
        sender = User.create!
        receiver = User.create!
        t1 = Transaction.create!(sender: sender, receiver: receiver)
        t2 = Transaction.create!(sender: receiver, receiver: sender)

        ability = Ability.new(sender)
        ability.can :read, Transaction, sender: { id: sender.id }
        ability.can :read, Transaction, receiver: { id: sender.id }
        expect(Transaction.accessible_by(ability)).to eq([t1, t2])
      end
    end

    context 'when a table is references multiple times' do
      it 'can filter correctly on the different associations' do
        u1 = User.create!(name: 'pippo')
        u2 = User.create!(name: 'paperino')

        a1 = Article.create!(user: u1)
        a2 = Article.create!(user: u2)

        ability = Ability.new(u1)
        ability.can :read, Article, user: { id: u1.id }
        ability.can :read, Article, mentioned_users: { name: u1.name }
        ability.can :read, Article, mentioned_users: { mentioned_articles: { id: a2.id } }
        ability.can :read, Article, mentioned_users: { articles: { user: { name: 'deep' } } }
        ability.can :read, Article, mentioned_users: { articles: { mentioned_users: { name: 'd2' } } }
        expect(Article.accessible_by(ability)).to eq([a1])
      end
    end
  end
end
