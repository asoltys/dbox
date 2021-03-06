module Dbox
  class DatabaseError < RuntimeError; end

  class Database
    include Loggable

    DB_FILENAME = ".dbox.sqlite3"

    def self.create(remote_path, local_path)
      db = new(local_path)
      if db.bootstrapped?
        raise DatabaseError, "Database already initialized -- please use 'dbox pull' or 'dbox push'."
      end
      db.bootstrap(remote_path)
      db.migrate()
      db
    end

    def self.load(local_path)
      db = new(local_path)
      unless db.bootstrapped?
        raise DatabaseError, "Database not initialized -- please run 'dbox create' or 'dbox clone'."
      end
      db.migrate()
      db
    end

    def self.exists?(local_path)
      File.exists?(File.join(local_path, DB_FILENAME))
    end

    def self.migrate_from_old_db_format(old_db)
      new_db = create(old_db.remote_path, old_db.local_path)
      new_db.delete_entry_by_path("") # clear out root record
      new_db.migrate_entry_from_old_db_format(old_db.root)
    end

    attr_reader :local_path

    # IMPORTANT: Database.new is private. Please use Database.create
    # or Database.load as the entry point.
    private_class_method :new
    def initialize(local_path)
      @local_path = local_path
      FileUtils.mkdir_p(local_path)
      @db = SQLite3::Database.new(File.join(local_path, DB_FILENAME))
      @db.trace {|sql| log.debug sql.strip }
      @db.execute("PRAGMA foreign_keys = ON;")
      ensure_schema_exists
    end

    def ensure_schema_exists
      @db.execute_batch(%{
        CREATE TABLE IF NOT EXISTS metadata (
          id           integer PRIMARY KEY AUTOINCREMENT NOT NULL,
          remote_path  varchar(255) NOT NULL,
          version      integer NOT NULL
        );
        CREATE TABLE IF NOT EXISTS entries (
          id           integer PRIMARY KEY AUTOINCREMENT NOT NULL,
          path         varchar(255) UNIQUE NOT NULL,
          is_dir       boolean NOT NULL,
          parent_id    integer REFERENCES entries(id) ON DELETE CASCADE,
          hash         varchar(255),
          modified     datetime,
          revision     integer
        );
        CREATE INDEX IF NOT EXISTS entry_parent_ids ON entries(parent_id);
      })
    end

    def migrate
      if metadata[:version] < 2
        @db.execute_batch(%{
          BEGIN TRANSACTION;
          ALTER TABLE metadata RENAME TO metadata_old;
          CREATE TABLE metadata (
            id           integer PRIMARY KEY AUTOINCREMENT NOT NULL,
            remote_path  varchar(255) NOT NULL,
            version      integer NOT NULL
          );
          INSERT INTO metadata SELECT id, remote_path, version FROM metadata_old;
          DROP TABLE metadata_old;
          UPDATE metadata SET version = 2;
          COMMIT;
        })
      end
    end

    METADATA_COLS = [ :remote_path, :version ] # don't need to return id
    ENTRY_COLS    = [ :id, :path, :is_dir, :parent_id, :hash, :modified, :revision ]

    def bootstrap(remote_path)
      @db.execute(%{
        INSERT INTO metadata (remote_path, version) VALUES (?, ?);
      }, remote_path, 2)
      @db.execute(%{
        INSERT INTO entries (path, is_dir) VALUES (?, ?)
      }, "", 1)
    end

    def bootstrapped?
      n = @db.get_first_value(%{
        SELECT count(id) FROM metadata LIMIT 1;
      })
      n && n > 0
    end

    def metadata
      cols = METADATA_COLS
      res = @db.get_first_row(%{
        SELECT #{cols.join(',')} FROM metadata LIMIT 1;
      })
      out = { :local_path => local_path }
      out.merge!(make_fields(cols, res)) if res
      out
    end

    def update_metadata(fields)
      set_str = fields.keys.map {|k| "#{k}=?" }.join(",")
      @db.execute(%{
        UPDATE metadata SET #{set_str};
      }, *fields.values)
    end

    def root_dir
      find_entry("WHERE parent_id is NULL")
    end

    def find_by_path(path)
      raise(ArgumentError, "path cannot be null") unless path
      find_entry("WHERE path=?", path)
    end

    def contents(dir_id)
      raise(ArgumentError, "dir_id cannot be null") unless dir_id
      find_entries("WHERE parent_id=?", dir_id)
    end

    def subdirs(dir_id)
      raise(ArgumentError, "dir_id cannot be null") unless dir_id
      find_entries("WHERE parent_id=? AND is_dir=1", dir_id)
    end

    def add_entry(path, is_dir, parent_id, modified, revision, hash)
      insert_entry(:path => path, :is_dir => is_dir, :parent_id => parent_id, :modified => modified, :revision => revision, :hash => hash)
    end

    def update_entry_by_path(path, fields)
      raise(ArgumentError, "path cannot be null") unless path
      update_entry(["WHERE path=?", path], fields)
    end

    def delete_entry_by_path(path)
      delete_entry_by_entry(find_by_path(path))
    end

    def delete_entry_by_entry(entry)
      raise(ArgumentError, "entry cannot be null") unless entry

      # cascade delete children, if any
      contents(entry[:id]).each {|child| delete_entry_by_entry(child) }

      # delete main entry
      delete_entry("WHERE id=?", entry[:id])
    end

    def migrate_entry_from_old_db_format(entry, parent = nil)
      # insert entry into sqlite db
      add_entry(entry.path, entry.dir?, (parent ? parent[:id] : nil), entry.modified_at, entry.revision, nil)

      # recur on children
      if entry.dir?
        new_parent = find_by_path(entry.path)
        entry.contents.each {|child_path, child| migrate_entry_from_old_db_format(child, new_parent) }
      end
    end

    private

    def find_entry(conditions = "", *args)
      res = @db.get_first_row(%{
        SELECT #{ENTRY_COLS.join(",")} FROM entries #{conditions} LIMIT 1;
      }, *args)
      entry_res_to_fields(res)
    end

    def find_entries(conditions = "", *args)
      out = []
      @db.execute(%{
        SELECT #{ENTRY_COLS.join(",")} FROM entries #{conditions} ORDER BY path ASC;
      }, *args) do |res|
        out << entry_res_to_fields(res)
      end
      out
    end

    def insert_entry(fields)
      log.debug "Inserting entry: #{fields.inspect}"
      h = fields.clone
      h[:modified]  = h[:modified].to_i if h[:modified]
      h[:is_dir] = (h[:is_dir] ? 1 : 0) unless h[:is_dir].nil?
      @db.execute(%{
        INSERT INTO entries (#{h.keys.join(",")})
        VALUES (#{(["?"] * h.size).join(",")});
      }, *h.values)
    end

    def update_entry(where_clause, fields)
      log.debug "Updating entry: #{where_clause}, #{fields.inspect}"
      h = fields.clone
      h[:modified]  = h[:modified].to_i if h[:modified]
      conditions, *args = *where_clause
      set_str = h.keys.map {|k| "#{k}=?" }.join(",")
      @db.execute(%{
        UPDATE entries SET #{set_str} #{conditions};
      }, *(h.values + args))
    end

    def delete_entry(conditions = "", *args)
      @db.execute(%{
        DELETE FROM entries #{conditions};
      }, *args)
    end

    def entry_res_to_fields(res)
      if res
        h = make_fields(ENTRY_COLS, res)
        h[:is_dir] = (h[:is_dir] == 1)
        h[:modified]  = Time.at(h[:modified]) if h[:modified]
        h.delete(:hash) unless h[:is_dir]
        h
      else
        nil
      end
    end

    def make_fields(keys, vals)
      if keys && vals
        raise ArgumentError.new("Can't make a fields hash with #{keys.size} keys and #{vals.size} vals") unless keys.size == vals.size
        out = {}
        keys.each_with_index {|k, i| out[k] = vals[i] }
        out
      else
        nil
      end
    end
  end
end
